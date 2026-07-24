#include "compute-internal.hpp"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <limits>
#include <memory>
#include <new>
#include <utility>
#include <vector>

static GpComputeEngine cpp_engine{
    1, GP_COMPUTE_ENGINE_CPP, "cpp", "host", nullptr, true
};

void gp_compute_set_error(char *error, size_t error_size, const char *message) {
    if (error == nullptr || error_size == 0) return;
    const size_t n = std::min(error_size - 1, std::strlen(message));
    std::memcpy(error, message, n);
    error[n] = '\0';
}

size_t gp_compute_dtype_size(int dtype) {
    switch (dtype) {
        case GP_COMPUTE_F32: return sizeof(float);
        case GP_COMPUTE_F64: return sizeof(double);
        case GP_COMPUTE_I32: return sizeof(int32_t);
        default: return 0;
    }
}

static bool checked_count(const int64_t *shape, int32_t rank, uint64_t *count,
                          char *error, size_t error_size) {
    if (rank <= 0) {
            gp_compute_set_error(error, error_size, "rank must be positive");
        return false;
    }
    uint64_t result = 1;
    for (int32_t axis = 0; axis < rank; ++axis) {
        if (shape[axis] < 0) {
            gp_compute_set_error(error, error_size, "shape dimensions must not be negative");
            return false;
        }
        const uint64_t dimension = static_cast<uint64_t>(shape[axis]);
        if (dimension != 0 && result > std::numeric_limits<uint64_t>::max() / dimension) {
            gp_compute_set_error(error, error_size, "shape is too large");
            return false;
        }
        result *= dimension;
    }
    *count = result;
    return true;
}

static void retain_storage(GpComputeStorage *storage) {
    storage->references.fetch_add(1, std::memory_order_relaxed);
}

static void release_storage(GpComputeStorage *storage) {
    if (storage == nullptr) return;
    if (storage->references.fetch_sub(1, std::memory_order_acq_rel) == 1) {
        if (storage->engine->kind == GP_COMPUTE_ENGINE_OPENCL) {
            gp_opencl_storage_free(storage->engine, storage->data);
        } else {
            std::free(storage->data);
        }
        gp_compute_engine_free(storage->engine);
        delete storage;
    }
}

uint64_t gp_compute_internal_view_count(const GpComputeView *view) {
    uint64_t result = 1;
    for (const int64_t dimension : view->shape) {
        result *= static_cast<uint64_t>(dimension);
    }
    return result;
}

uint64_t gp_compute_internal_storage_offset(const GpComputeView *view, uint64_t index) {
    uint64_t offset = view->offset;
    for (size_t axis = view->shape.size(); axis-- > 0;) {
        const uint64_t dimension = static_cast<uint64_t>(view->shape[axis]);
        const uint64_t coordinate = dimension == 0 ? 0 : index % dimension;
        if (dimension != 0) index /= dimension;
        offset += coordinate * static_cast<uint64_t>(view->strides[axis]);
    }
    return offset;
}

static bool same_shape(const GpComputeView *a, const GpComputeView *b) {
    return a->shape == b->shape;
}

static bool compatible(const GpComputeView *a, const GpComputeView *b,
                       char *error, size_t error_size) {
    if (a->storage->engine != b->storage->engine) {
        gp_compute_set_error(error, error_size, "views belong to different engines");
        return false;
    }
    if (a->storage->dtype != b->storage->dtype) {
        gp_compute_set_error(error, error_size, "views have different dtypes");
        return false;
    }
    if (!same_shape(a, b)) {
        gp_compute_set_error(error, error_size, "views have different shapes");
        return false;
    }
    return true;
}

static bool convert_value(int dtype, double value, void *destination,
                          char *error, size_t error_size) {
    switch (dtype) {
        case GP_COMPUTE_F32:
            *static_cast<float *>(destination) = static_cast<float>(value);
            return true;
        case GP_COMPUTE_F64:
            *static_cast<double *>(destination) = value;
            return true;
        case GP_COMPUTE_I32:
            if (!std::isfinite(value) || std::trunc(value) != value ||
                value < std::numeric_limits<int32_t>::min() ||
                value > std::numeric_limits<int32_t>::max()) {
                gp_compute_set_error(error, error_size, "value cannot be represented as i32");
                return false;
            }
            *static_cast<int32_t *>(destination) = static_cast<int32_t>(value);
            return true;
        default:
            gp_compute_set_error(error, error_size, "unsupported dtype");
            return false;
    }
}

static double read_value(const GpComputeView *view, uint64_t index) {
    const uint64_t offset = gp_compute_internal_storage_offset(view, index);
    switch (view->storage->dtype) {
        case GP_COMPUTE_F32: return static_cast<float *>(view->storage->data)[offset];
        case GP_COMPUTE_F64: return static_cast<double *>(view->storage->data)[offset];
        case GP_COMPUTE_I32: return static_cast<int32_t *>(view->storage->data)[offset];
        default: return 0.0;
    }
}

static bool write_value(GpComputeView *view, uint64_t index, double value,
                        char *error, size_t error_size) {
    const uint64_t offset = gp_compute_internal_storage_offset(view, index);
    const size_t width = gp_compute_dtype_size(view->storage->dtype);
    auto *destination = static_cast<unsigned char *>(view->storage->data) + offset * width;
    return convert_value(view->storage->dtype, value, destination, error, error_size);
}

static bool value_fits(int dtype, double value, char *error, size_t error_size) {
    alignas(double) unsigned char destination[sizeof(double)];
    return convert_value(dtype, value, destination, error, error_size);
}

extern "C" GpComputeEngine *gp_compute_cpp_engine(void) {
    return &cpp_engine;
}

extern "C" void gp_compute_engine_retain(GpComputeEngine *engine) {
    if (engine == nullptr || engine->immortal) return;
    engine->references.fetch_add(1, std::memory_order_relaxed);
}

extern "C" void gp_compute_engine_free(GpComputeEngine *engine) {
    if (engine == nullptr || engine->immortal) return;
    if (engine->references.fetch_sub(1, std::memory_order_acq_rel) == 1) {
        if (engine->kind == GP_COMPUTE_ENGINE_OPENCL) {
            gp_opencl_engine_destroy(engine);
        }
        delete engine;
    }
}

extern "C" const char *gp_compute_engine_name(const GpComputeEngine *engine) {
    return engine == nullptr ? "" : engine->name;
}

extern "C" const char *gp_compute_engine_device_name(const GpComputeEngine *engine) {
    return engine == nullptr ? "" : engine->device_name;
}

extern "C" int gp_compute_engine_sync(GpComputeEngine *engine,
                                       char *error, size_t error_size) {
    if (engine == nullptr) {
        gp_compute_set_error(error, error_size, "compute engine is closed");
        return -1;
    }
    if (engine->kind == GP_COMPUTE_ENGINE_OPENCL) {
        return gp_opencl_sync(engine, error, error_size);
    }
    return 0;
}

extern "C" GpComputeView *gp_compute_view_new(GpComputeEngine *engine, int dtype,
                                               const int64_t *shape, int32_t rank,
                                               char *error, size_t error_size) {
    if (engine == nullptr ||
        (engine->kind != GP_COMPUTE_ENGINE_CPP &&
         engine->kind != GP_COMPUTE_ENGINE_OPENCL)) {
        gp_compute_set_error(error, error_size, "unsupported compute engine");
        return nullptr;
    }
    const size_t width = gp_compute_dtype_size(dtype);
    if (width == 0) {
        gp_compute_set_error(error, error_size, "unsupported dtype");
        return nullptr;
    }
    uint64_t count = 0;
    if (!checked_count(shape, rank, &count, error, error_size)) return nullptr;
    if (count > std::numeric_limits<size_t>::max() / width) {
        gp_compute_set_error(error, error_size, "allocation is too large");
        return nullptr;
    }

    auto *storage = new (std::nothrow) GpComputeStorage();
    if (storage == nullptr) {
        gp_compute_set_error(error, error_size, "out of memory while creating storage");
        return nullptr;
    }
    bool allocated = false;
    if (engine->kind == GP_COMPUTE_ENGINE_OPENCL) {
        allocated = gp_opencl_storage_allocate(engine, dtype, count, &storage->data,
                                               error, error_size);
    } else {
        const size_t bytes = static_cast<size_t>(count) * width;
        storage->data = std::calloc(bytes == 0 ? 1 : bytes, 1);
        allocated = storage->data != nullptr;
        if (!allocated) {
            gp_compute_set_error(error, error_size, "out of memory while allocating storage");
        }
    }
    if (!allocated) {
        delete storage;
        return nullptr;
    }
    gp_compute_engine_retain(engine);
    storage->engine = engine;
    storage->dtype = dtype;
    storage->count = count;

    try {
        auto view = std::make_unique<GpComputeView>();
        view->shape.assign(shape, shape + rank);
        view->strides.resize(static_cast<size_t>(rank));
        int64_t stride = 1;
        for (int32_t axis = rank; axis-- > 0;) {
            view->strides[static_cast<size_t>(axis)] = stride;
            if (shape[axis] != 0 &&
                stride > std::numeric_limits<int64_t>::max() / shape[axis]) {
                release_storage(storage);
                gp_compute_set_error(error, error_size, "shape strides are too large");
                return nullptr;
            }
            stride *= shape[axis];
        }
        view->storage = storage;
        return view.release();
    } catch (const std::exception &) {
        release_storage(storage);
        gp_compute_set_error(error, error_size, "out of memory while creating view");
        return nullptr;
    }
}

extern "C" GpComputeView *gp_compute_view_slice(const GpComputeView *view,
                                                 int64_t start, int64_t length,
                                                 char *error, size_t error_size) {
    if (view->shape.size() != 1) {
        gp_compute_set_error(error, error_size, "slice currently requires a vector");
        return nullptr;
    }
    if (start < 0 || length < 0 || start > view->shape[0] ||
        length > view->shape[0] - start) {
        gp_compute_set_error(error, error_size, "slice is outside the vector");
        return nullptr;
    }
    try {
        auto result = std::make_unique<GpComputeView>();
        result->offset = view->offset + static_cast<uint64_t>(start * view->strides[0]);
        result->shape = {length};
        result->strides = view->strides;
        result->storage = view->storage;
        retain_storage(result->storage);
        return result.release();
    } catch (const std::exception &) {
        gp_compute_set_error(error, error_size, "out of memory while creating slice");
        return nullptr;
    }
}

extern "C" GpComputeView *gp_compute_view_row(const GpComputeView *view, int64_t row,
                                               char *error, size_t error_size) {
    if (view->shape.size() != 2) {
        gp_compute_set_error(error, error_size, "row currently requires a matrix");
        return nullptr;
    }
    if (row < 0 || row >= view->shape[0]) {
        gp_compute_set_error(error, error_size, "row is outside the matrix");
        return nullptr;
    }
    try {
        auto result = std::make_unique<GpComputeView>();
        result->offset = view->offset + static_cast<uint64_t>(row * view->strides[0]);
        result->shape = {view->shape[1]};
        result->strides = {view->strides[1]};
        result->storage = view->storage;
        retain_storage(result->storage);
        return result.release();
    } catch (const std::exception &) {
        gp_compute_set_error(error, error_size, "out of memory while creating row view");
        return nullptr;
    }
}

extern "C" GpComputeView *gp_compute_view_transpose(const GpComputeView *view,
                                                     char *error, size_t error_size) {
    if (view->shape.size() != 2) {
        gp_compute_set_error(error, error_size, "transpose currently requires a matrix");
        return nullptr;
    }
    try {
        auto result = std::make_unique<GpComputeView>();
        result->offset = view->offset;
        result->shape = {view->shape[1], view->shape[0]};
        result->strides = {view->strides[1], view->strides[0]};
        result->storage = view->storage;
        retain_storage(result->storage);
        return result.release();
    } catch (const std::exception &) {
        gp_compute_set_error(error, error_size, "out of memory while creating transpose view");
        return nullptr;
    }
}

extern "C" void gp_compute_view_free(GpComputeView *view) {
    if (view == nullptr) return;
    release_storage(view->storage);
    delete view;
}

extern "C" int gp_compute_view_dtype(const GpComputeView *view) {
    return view->storage->dtype;
}

extern "C" int32_t gp_compute_view_rank(const GpComputeView *view) {
    return static_cast<int32_t>(view->shape.size());
}

extern "C" int64_t gp_compute_view_shape(const GpComputeView *view, int32_t axis) {
    return view->shape[static_cast<size_t>(axis)];
}

extern "C" int64_t gp_compute_view_stride(const GpComputeView *view, int32_t axis) {
    return view->strides[static_cast<size_t>(axis)];
}

extern "C" uint64_t gp_compute_view_count(const GpComputeView *view) {
    return gp_compute_internal_view_count(view);
}

extern "C" uintptr_t gp_compute_view_storage_id(const GpComputeView *view) {
    return reinterpret_cast<uintptr_t>(view->storage);
}

extern "C" GpComputeEngine *gp_compute_view_engine(const GpComputeView *view) {
    return view->storage->engine;
}

extern "C" int gp_compute_view_get(const GpComputeView *view, uint64_t index,
                                    double *value, char *error, size_t error_size) {
    if (index >= gp_compute_internal_view_count(view)) {
        gp_compute_set_error(error, error_size, "index is outside the view");
        return -1;
    }
    if (view->storage->engine->kind == GP_COMPUTE_ENGINE_OPENCL) {
        return gp_opencl_read(view, index, value, error, error_size) ? 0 : -1;
    }
    *value = read_value(view, index);
    return 0;
}

extern "C" int gp_compute_view_set(GpComputeView *view, uint64_t index, double value,
                                    char *error, size_t error_size) {
    if (index >= gp_compute_internal_view_count(view)) {
        gp_compute_set_error(error, error_size, "index is outside the view");
        return -1;
    }
    if (view->storage->engine->kind == GP_COMPUTE_ENGINE_OPENCL) {
        return gp_opencl_write(view, index, value, error, error_size) ? 0 : -1;
    }
    return write_value(view, index, value, error, error_size) ? 0 : -1;
}

extern "C" int gp_compute_fill(GpComputeView *view, double value,
                                char *error, size_t error_size) {
    if (view->storage->engine->kind == GP_COMPUTE_ENGINE_OPENCL) {
        return gp_opencl_fill(view, value, error, error_size);
    }
    const uint64_t count = gp_compute_internal_view_count(view);
    for (uint64_t i = 0; i < count; ++i) {
        if (!write_value(view, i, value, error, error_size)) return -1;
    }
    return 0;
}

extern "C" int gp_compute_copy(GpComputeView *destination, const GpComputeView *source,
                                char *error, size_t error_size) {
    if (!compatible(destination, source, error, error_size)) return -1;
    if (destination->storage->engine->kind == GP_COMPUTE_ENGINE_OPENCL) {
        return gp_opencl_copy(destination, source, error, error_size);
    }
    try {
        const uint64_t count = gp_compute_internal_view_count(source);
        std::vector<double> values(static_cast<size_t>(count));
        for (uint64_t i = 0; i < count; ++i) values[static_cast<size_t>(i)] = read_value(source, i);
        for (uint64_t i = 0; i < count; ++i) {
            if (!write_value(destination, i, values[static_cast<size_t>(i)], error, error_size)) return -1;
        }
        return 0;
    } catch (const std::exception &) {
        gp_compute_set_error(error, error_size, "out of memory while copying view");
        return -1;
    }
}

extern "C" int gp_compute_scal(GpComputeView *view, double alpha,
                                char *error, size_t error_size) {
    if (view->storage->engine->kind == GP_COMPUTE_ENGINE_OPENCL) {
        return gp_opencl_scal(view, alpha, error, error_size);
    }
    try {
        const uint64_t count = gp_compute_internal_view_count(view);
        std::vector<double> values(static_cast<size_t>(count));
        for (uint64_t i = 0; i < count; ++i) {
            values[static_cast<size_t>(i)] = alpha * read_value(view, i);
            if (!value_fits(view->storage->dtype, values[static_cast<size_t>(i)],
                            error, error_size)) {
                return -1;
            }
        }
        for (uint64_t i = 0; i < count; ++i) {
            write_value(view, i, values[static_cast<size_t>(i)], error, error_size);
        }
        return 0;
    } catch (const std::exception &) {
        gp_compute_set_error(error, error_size, "out of memory while scaling view");
        return -1;
    }
}

extern "C" int gp_compute_axpy(GpComputeView *y, double alpha, const GpComputeView *x,
                                char *error, size_t error_size) {
    if (!compatible(y, x, error, error_size)) return -1;
    if (y->storage->engine->kind == GP_COMPUTE_ENGINE_OPENCL) {
        return gp_opencl_axpy(y, alpha, x, error, error_size);
    }
    try {
        const uint64_t count = gp_compute_internal_view_count(x);
        std::vector<double> values(static_cast<size_t>(count));
        for (uint64_t i = 0; i < count; ++i) {
            values[static_cast<size_t>(i)] =
                alpha * read_value(x, i) + read_value(y, i);
            if (!value_fits(y->storage->dtype, values[static_cast<size_t>(i)],
                            error, error_size)) {
                return -1;
            }
        }
        for (uint64_t i = 0; i < count; ++i) {
            write_value(y, i, values[static_cast<size_t>(i)], error, error_size);
        }
        return 0;
    } catch (const std::exception &) {
        gp_compute_set_error(error, error_size, "out of memory while computing axpy");
        return -1;
    }
}

extern "C" int gp_compute_dot(const GpComputeView *x, const GpComputeView *y,
                               double *result, char *error, size_t error_size) {
    if (!compatible(x, y, error, error_size)) return -1;
    if (x->shape.size() != 1) {
        gp_compute_set_error(error, error_size, "dot requires vectors");
        return -1;
    }
    if (x->storage->engine->kind == GP_COMPUTE_ENGINE_OPENCL) {
        return gp_opencl_dot(x, y, result, error, error_size);
    }
    double value = 0.0;
    const uint64_t count = gp_compute_internal_view_count(x);
    for (uint64_t i = 0; i < count; ++i) value += read_value(x, i) * read_value(y, i);
    *result = value;
    return 0;
}

extern "C" GpComputeView *gp_compute_mm(const GpComputeView *a, const GpComputeView *b,
                                         char *error, size_t error_size) {
    if (a->storage->engine != b->storage->engine) {
        gp_compute_set_error(error, error_size, "matrices belong to different engines");
        return nullptr;
    }
    if (a->storage->dtype != b->storage->dtype) {
        gp_compute_set_error(error, error_size, "matrices have different dtypes");
        return nullptr;
    }
    if (a->shape.size() != 2 || b->shape.size() != 2) {
        gp_compute_set_error(error, error_size, "matrix multiplication requires matrices");
        return nullptr;
    }
    if (a->shape[1] != b->shape[0]) {
        gp_compute_set_error(error, error_size, "matrix dimensions are incompatible");
        return nullptr;
    }
    if (a->storage->engine->kind == GP_COMPUTE_ENGINE_OPENCL) {
        return gp_opencl_mm(a, b, error, error_size);
    }
    const int64_t shape[2] = {a->shape[0], b->shape[1]};
    GpComputeView *result = gp_compute_view_new(a->storage->engine, a->storage->dtype,
                                                shape, 2, error, error_size);
    if (result == nullptr) return nullptr;
    for (int64_t row = 0; row < shape[0]; ++row) {
        for (int64_t column = 0; column < shape[1]; ++column) {
            double value = 0.0;
            for (int64_t inner = 0; inner < a->shape[1]; ++inner) {
                const uint64_t ai = static_cast<uint64_t>(row * a->shape[1] + inner);
                const uint64_t bi = static_cast<uint64_t>(inner * b->shape[1] + column);
                value += read_value(a, ai) * read_value(b, bi);
            }
            const uint64_t ri = static_cast<uint64_t>(row * shape[1] + column);
            if (!write_value(result, ri, value, error, error_size)) {
                gp_compute_view_free(result);
                return nullptr;
            }
        }
    }
    return result;
}

extern "C" GpComputeView *gp_compute_transfer(GpComputeEngine *engine,
                                               const GpComputeView *source,
                                               char *error, size_t error_size) {
    GpComputeView *destination =
        gp_compute_view_new(engine, source->storage->dtype, source->shape.data(),
                            static_cast<int32_t>(source->shape.size()),
                            error, error_size);
    if (destination == nullptr) return nullptr;
    const uint64_t count = gp_compute_internal_view_count(source);
    for (uint64_t index = 0; index < count; ++index) {
        double value = 0.0;
        if (gp_compute_view_get(source, index, &value, error, error_size) < 0 ||
            gp_compute_view_set(destination, index, value, error, error_size) < 0) {
            gp_compute_view_free(destination);
            return nullptr;
        }
    }
    return destination;
}

extern "C" GpComputeQueue *gp_compute_queue_new(
    GpComputeEngine *engine, char *error, size_t error_size) {
    if (engine == nullptr) {
        gp_compute_set_error(error, error_size, "compute engine is closed");
        return nullptr;
    }
    auto queue = std::unique_ptr<GpComputeQueue>(
        new (std::nothrow) GpComputeQueue());
    if (!queue) {
        gp_compute_set_error(error, error_size, "out of memory while creating queue");
        return nullptr;
    }
    if (engine->kind == GP_COMPUTE_ENGINE_OPENCL &&
        !gp_opencl_queue_new(engine, &queue->state, error, error_size)) {
        return nullptr;
    }
    gp_compute_engine_retain(engine);
    queue->engine = engine;
    return queue.release();
}

extern "C" void gp_compute_queue_free(GpComputeQueue *queue) {
    if (queue == nullptr) return;
    if (queue->engine != nullptr &&
        queue->engine->kind == GP_COMPUTE_ENGINE_OPENCL) {
        gp_opencl_queue_free(queue->state);
    }
    gp_compute_engine_free(queue->engine);
    delete queue;
}

extern "C" GpComputeEngine *gp_compute_queue_engine(
    const GpComputeQueue *queue) {
    return queue->engine;
}

extern "C" int gp_compute_queue_finish(
    GpComputeQueue *queue, char *error, size_t error_size) {
    if (queue->engine->kind == GP_COMPUTE_ENGINE_OPENCL) {
        return gp_opencl_queue_finish(queue->state, error, error_size);
    }
    return 0;
}

extern "C" void gp_compute_event_free(GpComputeEvent *event) {
    if (event == nullptr) return;
    if (event->engine != nullptr &&
        event->engine->kind == GP_COMPUTE_ENGINE_OPENCL) {
        gp_opencl_event_free(event->state);
    }
    gp_compute_engine_free(event->engine);
    delete event;
}

extern "C" GpComputeEngine *gp_compute_event_engine(
    const GpComputeEvent *event) {
    return event->engine;
}

extern "C" int gp_compute_event_wait(
    GpComputeEvent *event, char *error, size_t error_size) {
    if (event->engine->kind == GP_COMPUTE_ENGINE_OPENCL) {
        const int status =
            gp_opencl_event_wait(event->state, error, error_size);
        if (status == 0) event->complete = true;
        return status;
    }
    event->complete = true;
    return 0;
}

extern "C" int gp_compute_event_complete(
    GpComputeEvent *event, char *error, size_t error_size) {
    if (event->complete) return 1;
    if (event->engine->kind == GP_COMPUTE_ENGINE_OPENCL) {
        const int status =
            gp_opencl_event_complete(event->state, error, error_size);
        if (status > 0) event->complete = true;
        return status;
    }
    event->complete = true;
    return 1;
}

extern "C" GpComputeEvent *gp_compute_enqueue_fill(
    GpComputeQueue *queue, GpComputeView *view, double value,
    GpComputeEvent *const *dependencies, int32_t dependency_count,
    char *error, size_t error_size) {
    if (queue->engine != view->storage->engine) {
        gp_compute_set_error(
            error, error_size,
            "queue and view belong to different engines");
        return nullptr;
    }
    for (int32_t index = 0; index < dependency_count; ++index) {
        if (dependencies[index] == nullptr ||
            dependencies[index]->engine != queue->engine) {
            gp_compute_set_error(
                error, error_size,
                "event dependency belongs to a different engine");
            return nullptr;
        }
    }
    auto event = std::unique_ptr<GpComputeEvent>(
        new (std::nothrow) GpComputeEvent());
    if (!event) {
        gp_compute_set_error(error, error_size, "out of memory while creating event");
        return nullptr;
    }
    if (queue->engine->kind == GP_COMPUTE_ENGINE_OPENCL) {
        if (!gp_opencl_enqueue_fill(queue, view, value, dependencies,
                                    dependency_count, &event->state,
                                    error, error_size)) {
            return nullptr;
        }
    } else {
        for (int32_t index = 0; index < dependency_count; ++index) {
            if (gp_compute_event_wait(
                    dependencies[index], error, error_size) < 0) {
                return nullptr;
            }
        }
        if (gp_compute_fill(view, value, error, error_size) < 0) return nullptr;
        event->complete = true;
    }
    gp_compute_engine_retain(queue->engine);
    event->engine = queue->engine;
    return event.release();
}

extern "C" GpComputeEvent *gp_compute_enqueue_copy(
    GpComputeQueue *queue, GpComputeView *destination,
    const GpComputeView *source,
    GpComputeEvent *const *dependencies, int32_t dependency_count,
    char *error, size_t error_size) {
    if (!compatible(destination, source, error, error_size)) return nullptr;
    if (queue->engine != destination->storage->engine) {
        gp_compute_set_error(
            error, error_size,
            "queue and views belong to different engines");
        return nullptr;
    }
    for (int32_t index = 0; index < dependency_count; ++index) {
        if (dependencies[index] == nullptr ||
            dependencies[index]->engine != queue->engine) {
            gp_compute_set_error(
                error, error_size,
                "event dependency belongs to a different engine");
            return nullptr;
        }
    }
    auto event = std::unique_ptr<GpComputeEvent>(
        new (std::nothrow) GpComputeEvent());
    if (!event) {
        gp_compute_set_error(error, error_size, "out of memory while creating event");
        return nullptr;
    }
    if (queue->engine->kind == GP_COMPUTE_ENGINE_OPENCL) {
        if (!gp_opencl_enqueue_copy(
                queue, destination, source, dependencies, dependency_count,
                &event->state, error, error_size)) {
            return nullptr;
        }
    } else {
        for (int32_t index = 0; index < dependency_count; ++index) {
            if (gp_compute_event_wait(
                    dependencies[index], error, error_size) < 0) {
                return nullptr;
            }
        }
        if (gp_compute_copy(destination, source, error, error_size) < 0) {
            return nullptr;
        }
        event->complete = true;
    }
    gp_compute_engine_retain(queue->engine);
    event->engine = queue->engine;
    return event.release();
}

static bool validate_async_dependencies(
    const GpComputeQueue *queue,
    GpComputeEvent *const *dependencies, int32_t dependency_count,
    char *error, size_t error_size) {
    for (int32_t index = 0; index < dependency_count; ++index) {
        if (dependencies[index] == nullptr ||
            dependencies[index]->engine != queue->engine) {
            gp_compute_set_error(
                error, error_size,
                "event dependency belongs to a different engine");
            return false;
        }
    }
    return true;
}

static bool wait_async_dependencies(
    GpComputeEvent *const *dependencies, int32_t dependency_count,
    char *error, size_t error_size) {
    for (int32_t index = 0; index < dependency_count; ++index) {
        if (gp_compute_event_wait(
                dependencies[index], error, error_size) < 0) {
            return false;
        }
    }
    return true;
}

static GpComputeEvent *finish_async_event(
    std::unique_ptr<GpComputeEvent> event, GpComputeEngine *engine) {
    gp_compute_engine_retain(engine);
    event->engine = engine;
    return event.release();
}

extern "C" GpComputeEvent *gp_compute_enqueue_scal(
    GpComputeQueue *queue, GpComputeView *view, double alpha,
    GpComputeEvent *const *dependencies, int32_t dependency_count,
    char *error, size_t error_size) {
    if (queue->engine != view->storage->engine) {
        gp_compute_set_error(
            error, error_size,
            "queue and view belong to different engines");
        return nullptr;
    }
    if (!validate_async_dependencies(
            queue, dependencies, dependency_count, error, error_size)) {
        return nullptr;
    }
    auto event = std::unique_ptr<GpComputeEvent>(
        new (std::nothrow) GpComputeEvent());
    if (!event) {
        gp_compute_set_error(
            error, error_size, "out of memory while creating event");
        return nullptr;
    }
    if (queue->engine->kind == GP_COMPUTE_ENGINE_OPENCL) {
        if (!gp_opencl_enqueue_scal(
                queue, view, alpha, dependencies, dependency_count,
                &event->state, error, error_size)) {
            return nullptr;
        }
    } else {
        if (!wait_async_dependencies(
                dependencies, dependency_count, error, error_size) ||
            gp_compute_scal(view, alpha, error, error_size) < 0) {
            return nullptr;
        }
        event->complete = true;
    }
    return finish_async_event(std::move(event), queue->engine);
}

extern "C" GpComputeEvent *gp_compute_enqueue_axpy(
    GpComputeQueue *queue, GpComputeView *y, double alpha,
    const GpComputeView *x,
    GpComputeEvent *const *dependencies, int32_t dependency_count,
    char *error, size_t error_size) {
    if (!compatible(y, x, error, error_size)) return nullptr;
    if (queue->engine != y->storage->engine) {
        gp_compute_set_error(
            error, error_size,
            "queue and views belong to different engines");
        return nullptr;
    }
    if (!validate_async_dependencies(
            queue, dependencies, dependency_count, error, error_size)) {
        return nullptr;
    }
    auto event = std::unique_ptr<GpComputeEvent>(
        new (std::nothrow) GpComputeEvent());
    if (!event) {
        gp_compute_set_error(
            error, error_size, "out of memory while creating event");
        return nullptr;
    }
    if (queue->engine->kind == GP_COMPUTE_ENGINE_OPENCL) {
        if (!gp_opencl_enqueue_axpy(
                queue, y, alpha, x, dependencies, dependency_count,
                &event->state, error, error_size)) {
            return nullptr;
        }
    } else {
        if (!wait_async_dependencies(
                dependencies, dependency_count, error, error_size) ||
            gp_compute_axpy(y, alpha, x, error, error_size) < 0) {
            return nullptr;
        }
        event->complete = true;
    }
    return finish_async_event(std::move(event), queue->engine);
}

extern "C" GpComputeEvent *gp_compute_enqueue_dot(
    GpComputeQueue *queue, const GpComputeView *x, const GpComputeView *y,
    GpComputeView **result,
    GpComputeEvent *const *dependencies, int32_t dependency_count,
    char *error, size_t error_size) {
    *result = nullptr;
    if (!compatible(x, y, error, error_size)) return nullptr;
    if (x->shape.size() != 1) {
        gp_compute_set_error(error, error_size, "dot requires vectors");
        return nullptr;
    }
    if (queue->engine != x->storage->engine) {
        gp_compute_set_error(
            error, error_size,
            "queue and views belong to different engines");
        return nullptr;
    }
    if (!validate_async_dependencies(
            queue, dependencies, dependency_count, error, error_size)) {
        return nullptr;
    }
    auto event = std::unique_ptr<GpComputeEvent>(
        new (std::nothrow) GpComputeEvent());
    if (!event) {
        gp_compute_set_error(
            error, error_size, "out of memory while creating event");
        return nullptr;
    }
    const int64_t shape[1] = {1};
    std::unique_ptr<GpComputeView, decltype(&gp_compute_view_free)> output(
        gp_compute_view_new(queue->engine, x->storage->dtype, shape, 1,
                            error, error_size),
        gp_compute_view_free);
    if (!output) return nullptr;
    if (queue->engine->kind == GP_COMPUTE_ENGINE_OPENCL) {
        if (!gp_opencl_enqueue_dot(
                queue, x, y, output.get(), dependencies, dependency_count,
                &event->state, error, error_size)) {
            return nullptr;
        }
    } else {
        double value = 0.0;
        if (!wait_async_dependencies(
                dependencies, dependency_count, error, error_size) ||
            gp_compute_dot(x, y, &value, error, error_size) < 0 ||
            gp_compute_view_set(
                output.get(), 0, value, error, error_size) < 0) {
            return nullptr;
        }
        event->complete = true;
    }
    *result = output.release();
    return finish_async_event(std::move(event), queue->engine);
}

extern "C" GpComputeEvent *gp_compute_enqueue_mm(
    GpComputeQueue *queue, const GpComputeView *a, const GpComputeView *b,
    GpComputeView **result,
    GpComputeEvent *const *dependencies, int32_t dependency_count,
    char *error, size_t error_size) {
    *result = nullptr;
    if (a->storage->engine != b->storage->engine) {
        gp_compute_set_error(
            error, error_size, "matrices belong to different engines");
        return nullptr;
    }
    if (a->storage->dtype != b->storage->dtype) {
        gp_compute_set_error(
            error, error_size, "matrices have different dtypes");
        return nullptr;
    }
    if (a->shape.size() != 2 || b->shape.size() != 2) {
        gp_compute_set_error(
            error, error_size,
            "matrix multiplication requires matrices");
        return nullptr;
    }
    if (a->shape[1] != b->shape[0]) {
        gp_compute_set_error(
            error, error_size, "matrix dimensions are incompatible");
        return nullptr;
    }
    if (queue->engine != a->storage->engine) {
        gp_compute_set_error(
            error, error_size,
            "queue and matrices belong to different engines");
        return nullptr;
    }
    if (!validate_async_dependencies(
            queue, dependencies, dependency_count, error, error_size)) {
        return nullptr;
    }
    auto event = std::unique_ptr<GpComputeEvent>(
        new (std::nothrow) GpComputeEvent());
    if (!event) {
        gp_compute_set_error(
            error, error_size, "out of memory while creating event");
        return nullptr;
    }
    if (queue->engine->kind == GP_COMPUTE_ENGINE_OPENCL) {
        const int64_t shape[2] = {a->shape[0], b->shape[1]};
        std::unique_ptr<GpComputeView, decltype(&gp_compute_view_free)> output(
            gp_compute_view_new(queue->engine, a->storage->dtype, shape, 2,
                                error, error_size),
            gp_compute_view_free);
        if (!output ||
            !gp_opencl_enqueue_mm(
                queue, a, b, output.get(), dependencies, dependency_count,
                &event->state, error, error_size)) {
            return nullptr;
        }
        *result = output.release();
    } else {
        if (!wait_async_dependencies(
                dependencies, dependency_count, error, error_size)) {
            return nullptr;
        }
        *result = gp_compute_mm(a, b, error, error_size);
        if (*result == nullptr) return nullptr;
        event->complete = true;
    }
    return finish_async_event(std::move(event), queue->engine);
}

extern "C" GpComputeKernel *gp_compute_kernel_new(
    GpComputeEngine *engine, const char *name,
    const char *source, size_t source_length,
    char *error, size_t error_size) {
    if (engine == nullptr) {
        gp_compute_set_error(error, error_size, "compute engine is closed");
        return nullptr;
    }
    if (engine->kind != GP_COMPUTE_ENGINE_OPENCL) {
        gp_compute_set_error(
            error, error_size,
            "compiled kernels currently require an OpenCL engine");
        return nullptr;
    }
    if (name == nullptr || name[0] == '\0' ||
        source == nullptr || source_length == 0) {
        gp_compute_set_error(
            error, error_size, "kernel name and source cannot be empty");
        return nullptr;
    }
    auto kernel = std::unique_ptr<GpComputeKernel>(
        new (std::nothrow) GpComputeKernel());
    if (!kernel) {
        gp_compute_set_error(
            error, error_size, "out of memory while creating kernel");
        return nullptr;
    }
    if (!gp_opencl_kernel_new(
            engine, name, source, source_length, &kernel->state,
            error, error_size)) {
        return nullptr;
    }
    gp_compute_engine_retain(engine);
    kernel->engine = engine;
    return kernel.release();
}

extern "C" void gp_compute_kernel_free(GpComputeKernel *kernel) {
    if (kernel == nullptr) return;
    if (kernel->engine != nullptr &&
        kernel->engine->kind == GP_COMPUTE_ENGINE_OPENCL) {
        gp_opencl_kernel_free(kernel->state);
    }
    gp_compute_engine_free(kernel->engine);
    delete kernel;
}

extern "C" GpComputeEngine *gp_compute_kernel_engine(
    const GpComputeKernel *kernel) {
    return kernel->engine;
}

extern "C" GpComputeEvent *gp_compute_enqueue_kernel(
    GpComputeQueue *queue, GpComputeKernel *kernel,
    const uint64_t *global_sizes, int32_t work_dimension,
    const GpComputeKernelArgument *arguments, int32_t argument_count,
    GpComputeEvent *const *dependencies, int32_t dependency_count,
    char *error, size_t error_size) {
    if (queue == nullptr || kernel == nullptr ||
        queue->engine != kernel->engine) {
        gp_compute_set_error(
            error, error_size,
            "queue and compiled kernel belong to different engines");
        return nullptr;
    }
    if (work_dimension < 1 || work_dimension > 3) {
        gp_compute_set_error(
            error, error_size, "kernel work dimension must be between 1 and 3");
        return nullptr;
    }
    if (argument_count < 0 || dependency_count < 0 ||
        global_sizes == nullptr ||
        (argument_count > 0 && arguments == nullptr)) {
        gp_compute_set_error(error, error_size, "invalid kernel launch arguments");
        return nullptr;
    }
    if (!validate_async_dependencies(
            queue, dependencies, dependency_count, error, error_size)) {
        return nullptr;
    }
    for (int32_t index = 0; index < argument_count; ++index) {
        if (arguments[index].kind == GP_COMPUTE_KERNEL_VIEW &&
            (arguments[index].view == nullptr ||
             arguments[index].view->storage->engine != queue->engine)) {
            gp_compute_set_error(
                error, error_size,
                "kernel view argument belongs to a different engine");
            return nullptr;
        }
    }
    auto event = std::unique_ptr<GpComputeEvent>(
        new (std::nothrow) GpComputeEvent());
    if (!event) {
        gp_compute_set_error(
            error, error_size, "out of memory while creating kernel event");
        return nullptr;
    }
    if (!gp_opencl_enqueue_kernel(
            queue, kernel->state, global_sizes, work_dimension,
            arguments, argument_count, dependencies, dependency_count,
            &event->state, error, error_size)) {
        return nullptr;
    }
    if (event->state == nullptr) event->complete = true;
    return finish_async_event(std::move(event), queue->engine);
}
