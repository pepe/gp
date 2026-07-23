#include "compute-helper.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <limits>
#include <memory>
#include <new>
#include <utility>
#include <vector>

struct GpComputeEngine {
    const char *name;
};

struct GpComputeStorage {
    std::atomic<size_t> references{1};
    GpComputeEngine *engine = nullptr;
    int dtype = 0;
    uint64_t count = 0;
    void *data = nullptr;
};

struct GpComputeView {
    GpComputeStorage *storage = nullptr;
    uint64_t offset = 0;
    std::vector<int64_t> shape;
    std::vector<int64_t> strides;
};

static GpComputeEngine cpp_engine{"cpp"};

static void set_error(char *error, size_t error_size, const char *message) {
    if (error == nullptr || error_size == 0) return;
    const size_t n = std::min(error_size - 1, std::strlen(message));
    std::memcpy(error, message, n);
    error[n] = '\0';
}

static size_t dtype_size(int dtype) {
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
        set_error(error, error_size, "rank must be positive");
        return false;
    }
    uint64_t result = 1;
    for (int32_t axis = 0; axis < rank; ++axis) {
        if (shape[axis] < 0) {
            set_error(error, error_size, "shape dimensions must not be negative");
            return false;
        }
        const uint64_t dimension = static_cast<uint64_t>(shape[axis]);
        if (dimension != 0 && result > std::numeric_limits<uint64_t>::max() / dimension) {
            set_error(error, error_size, "shape is too large");
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
        std::free(storage->data);
        delete storage;
    }
}

static uint64_t view_count(const GpComputeView *view) {
    uint64_t result = 1;
    for (const int64_t dimension : view->shape) {
        result *= static_cast<uint64_t>(dimension);
    }
    return result;
}

static uint64_t storage_offset(const GpComputeView *view, uint64_t index) {
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
        set_error(error, error_size, "views belong to different engines");
        return false;
    }
    if (a->storage->dtype != b->storage->dtype) {
        set_error(error, error_size, "views have different dtypes");
        return false;
    }
    if (!same_shape(a, b)) {
        set_error(error, error_size, "views have different shapes");
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
                set_error(error, error_size, "value cannot be represented as i32");
                return false;
            }
            *static_cast<int32_t *>(destination) = static_cast<int32_t>(value);
            return true;
        default:
            set_error(error, error_size, "unsupported dtype");
            return false;
    }
}

static double read_value(const GpComputeView *view, uint64_t index) {
    const uint64_t offset = storage_offset(view, index);
    switch (view->storage->dtype) {
        case GP_COMPUTE_F32: return static_cast<float *>(view->storage->data)[offset];
        case GP_COMPUTE_F64: return static_cast<double *>(view->storage->data)[offset];
        case GP_COMPUTE_I32: return static_cast<int32_t *>(view->storage->data)[offset];
        default: return 0.0;
    }
}

static bool write_value(GpComputeView *view, uint64_t index, double value,
                        char *error, size_t error_size) {
    const uint64_t offset = storage_offset(view, index);
    const size_t width = dtype_size(view->storage->dtype);
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

extern "C" const char *gp_compute_engine_name(const GpComputeEngine *engine) {
    return engine == nullptr ? "" : engine->name;
}

extern "C" GpComputeView *gp_compute_view_new(GpComputeEngine *engine, int dtype,
                                               const int64_t *shape, int32_t rank,
                                               char *error, size_t error_size) {
    if (engine != &cpp_engine) {
        set_error(error, error_size, "unsupported compute engine");
        return nullptr;
    }
    const size_t width = dtype_size(dtype);
    if (width == 0) {
        set_error(error, error_size, "unsupported dtype");
        return nullptr;
    }
    uint64_t count = 0;
    if (!checked_count(shape, rank, &count, error, error_size)) return nullptr;
    if (count > std::numeric_limits<size_t>::max() / width) {
        set_error(error, error_size, "allocation is too large");
        return nullptr;
    }

    auto *storage = new (std::nothrow) GpComputeStorage();
    if (storage == nullptr) {
        set_error(error, error_size, "out of memory while creating storage");
        return nullptr;
    }
    const size_t bytes = static_cast<size_t>(count) * width;
    storage->data = std::calloc(bytes == 0 ? 1 : bytes, 1);
    if (storage->data == nullptr) {
        delete storage;
        set_error(error, error_size, "out of memory while allocating storage");
        return nullptr;
    }
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
                set_error(error, error_size, "shape strides are too large");
                return nullptr;
            }
            stride *= shape[axis];
        }
        view->storage = storage;
        return view.release();
    } catch (const std::exception &) {
        release_storage(storage);
        set_error(error, error_size, "out of memory while creating view");
        return nullptr;
    }
}

extern "C" GpComputeView *gp_compute_view_slice(const GpComputeView *view,
                                                 int64_t start, int64_t length,
                                                 char *error, size_t error_size) {
    if (view->shape.size() != 1) {
        set_error(error, error_size, "slice currently requires a vector");
        return nullptr;
    }
    if (start < 0 || length < 0 || start > view->shape[0] ||
        length > view->shape[0] - start) {
        set_error(error, error_size, "slice is outside the vector");
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
        set_error(error, error_size, "out of memory while creating slice");
        return nullptr;
    }
}

extern "C" GpComputeView *gp_compute_view_row(const GpComputeView *view, int64_t row,
                                               char *error, size_t error_size) {
    if (view->shape.size() != 2) {
        set_error(error, error_size, "row currently requires a matrix");
        return nullptr;
    }
    if (row < 0 || row >= view->shape[0]) {
        set_error(error, error_size, "row is outside the matrix");
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
        set_error(error, error_size, "out of memory while creating row view");
        return nullptr;
    }
}

extern "C" GpComputeView *gp_compute_view_transpose(const GpComputeView *view,
                                                     char *error, size_t error_size) {
    if (view->shape.size() != 2) {
        set_error(error, error_size, "transpose currently requires a matrix");
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
        set_error(error, error_size, "out of memory while creating transpose view");
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
    return view_count(view);
}

extern "C" uintptr_t gp_compute_view_storage_id(const GpComputeView *view) {
    return reinterpret_cast<uintptr_t>(view->storage);
}

extern "C" GpComputeEngine *gp_compute_view_engine(const GpComputeView *view) {
    return view->storage->engine;
}

extern "C" int gp_compute_view_get(const GpComputeView *view, uint64_t index,
                                    double *value, char *error, size_t error_size) {
    if (index >= view_count(view)) {
        set_error(error, error_size, "index is outside the view");
        return -1;
    }
    *value = read_value(view, index);
    return 0;
}

extern "C" int gp_compute_view_set(GpComputeView *view, uint64_t index, double value,
                                    char *error, size_t error_size) {
    if (index >= view_count(view)) {
        set_error(error, error_size, "index is outside the view");
        return -1;
    }
    return write_value(view, index, value, error, error_size) ? 0 : -1;
}

extern "C" int gp_compute_fill(GpComputeView *view, double value,
                                char *error, size_t error_size) {
    const uint64_t count = view_count(view);
    for (uint64_t i = 0; i < count; ++i) {
        if (!write_value(view, i, value, error, error_size)) return -1;
    }
    return 0;
}

extern "C" int gp_compute_copy(GpComputeView *destination, const GpComputeView *source,
                                char *error, size_t error_size) {
    if (!compatible(destination, source, error, error_size)) return -1;
    try {
        const uint64_t count = view_count(source);
        std::vector<double> values(static_cast<size_t>(count));
        for (uint64_t i = 0; i < count; ++i) values[static_cast<size_t>(i)] = read_value(source, i);
        for (uint64_t i = 0; i < count; ++i) {
            if (!write_value(destination, i, values[static_cast<size_t>(i)], error, error_size)) return -1;
        }
        return 0;
    } catch (const std::exception &) {
        set_error(error, error_size, "out of memory while copying view");
        return -1;
    }
}

extern "C" int gp_compute_scal(GpComputeView *view, double alpha,
                                char *error, size_t error_size) {
    try {
        const uint64_t count = view_count(view);
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
        set_error(error, error_size, "out of memory while scaling view");
        return -1;
    }
}

extern "C" int gp_compute_axpy(GpComputeView *y, double alpha, const GpComputeView *x,
                                char *error, size_t error_size) {
    if (!compatible(y, x, error, error_size)) return -1;
    try {
        const uint64_t count = view_count(x);
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
        set_error(error, error_size, "out of memory while computing axpy");
        return -1;
    }
}

extern "C" int gp_compute_dot(const GpComputeView *x, const GpComputeView *y,
                               double *result, char *error, size_t error_size) {
    if (!compatible(x, y, error, error_size)) return -1;
    if (x->shape.size() != 1) {
        set_error(error, error_size, "dot requires vectors");
        return -1;
    }
    double value = 0.0;
    const uint64_t count = view_count(x);
    for (uint64_t i = 0; i < count; ++i) value += read_value(x, i) * read_value(y, i);
    *result = value;
    return 0;
}

extern "C" GpComputeView *gp_compute_mm(const GpComputeView *a, const GpComputeView *b,
                                         char *error, size_t error_size) {
    if (a->storage->engine != b->storage->engine) {
        set_error(error, error_size, "matrices belong to different engines");
        return nullptr;
    }
    if (a->storage->dtype != b->storage->dtype) {
        set_error(error, error_size, "matrices have different dtypes");
        return nullptr;
    }
    if (a->shape.size() != 2 || b->shape.size() != 2) {
        set_error(error, error_size, "matrix multiplication requires matrices");
        return nullptr;
    }
    if (a->shape[1] != b->shape[0]) {
        set_error(error, error_size, "matrix dimensions are incompatible");
        return nullptr;
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
