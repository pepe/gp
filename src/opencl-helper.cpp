#include "compute-internal.hpp"

#define CL_TARGET_OPENCL_VERSION 300
#include <CL/cl.h>
#include <CL/cl_function_types.h>

#ifdef _WIN32
#define NOMINMAX
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#else
#include <dlfcn.h>
#endif

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <limits>
#include <memory>
#include <mutex>
#include <new>
#include <string>
#include <vector>

namespace {

struct OpenClApi {
#ifdef _WIN32
    HMODULE library = nullptr;
#else
    void *library = nullptr;
#endif
    clGetPlatformIDs_fn get_platform_ids = nullptr;
    clGetPlatformInfo_fn get_platform_info = nullptr;
    clGetDeviceIDs_fn get_device_ids = nullptr;
    clGetDeviceInfo_fn get_device_info = nullptr;
    clCreateContext_fn create_context = nullptr;
    clReleaseContext_fn release_context = nullptr;
    clCreateCommandQueue_fn create_command_queue = nullptr;
    clReleaseCommandQueue_fn release_command_queue = nullptr;
    clCreateBuffer_fn create_buffer = nullptr;
    clReleaseMemObject_fn release_mem = nullptr;
    clEnqueueReadBuffer_fn enqueue_read = nullptr;
    clEnqueueWriteBuffer_fn enqueue_write = nullptr;
    clEnqueueFillBuffer_fn enqueue_fill = nullptr;
    clCreateProgramWithSource_fn create_program = nullptr;
    clBuildProgram_fn build_program = nullptr;
    clGetProgramBuildInfo_fn get_program_build_info = nullptr;
    clReleaseProgram_fn release_program = nullptr;
    clCreateKernel_fn create_kernel = nullptr;
    clReleaseKernel_fn release_kernel = nullptr;
    clSetKernelArg_fn set_kernel_arg = nullptr;
    clEnqueueNDRangeKernel_fn enqueue_kernel = nullptr;
    clGetEventInfo_fn get_event_info = nullptr;
    clWaitForEvents_fn wait_for_events = nullptr;
    clReleaseEvent_fn release_event = nullptr;
    clFinish_fn finish = nullptr;
};

struct OpenClState {
    cl_platform_id platform = nullptr;
    cl_device_id device = nullptr;
    cl_context context = nullptr;
    cl_command_queue queue = nullptr;
    cl_program program = nullptr;
    std::string device_name;
    bool fp64 = false;

    ~OpenClState();
};

OpenClApi opencl;
std::once_flag opencl_once;
std::string opencl_load_error;

OpenClState::~OpenClState() {
    if (program != nullptr) opencl.release_program(program);
    if (queue != nullptr) opencl.release_command_queue(queue);
    if (context != nullptr) opencl.release_context(context);
}

const char *cl_error_name(cl_int code) {
    switch (code) {
        case CL_SUCCESS: return "CL_SUCCESS";
        case CL_DEVICE_NOT_FOUND: return "CL_DEVICE_NOT_FOUND";
        case CL_DEVICE_NOT_AVAILABLE: return "CL_DEVICE_NOT_AVAILABLE";
        case CL_COMPILER_NOT_AVAILABLE: return "CL_COMPILER_NOT_AVAILABLE";
        case CL_MEM_OBJECT_ALLOCATION_FAILURE: return "CL_MEM_OBJECT_ALLOCATION_FAILURE";
        case CL_OUT_OF_RESOURCES: return "CL_OUT_OF_RESOURCES";
        case CL_OUT_OF_HOST_MEMORY: return "CL_OUT_OF_HOST_MEMORY";
        case CL_BUILD_PROGRAM_FAILURE: return "CL_BUILD_PROGRAM_FAILURE";
        case CL_INVALID_VALUE: return "CL_INVALID_VALUE";
        case CL_INVALID_DEVICE_TYPE: return "CL_INVALID_DEVICE_TYPE";
        case CL_INVALID_PLATFORM: return "CL_INVALID_PLATFORM";
        case CL_INVALID_DEVICE: return "CL_INVALID_DEVICE";
        case CL_INVALID_CONTEXT: return "CL_INVALID_CONTEXT";
        case CL_INVALID_COMMAND_QUEUE: return "CL_INVALID_COMMAND_QUEUE";
        case CL_INVALID_MEM_OBJECT: return "CL_INVALID_MEM_OBJECT";
        case CL_INVALID_PROGRAM: return "CL_INVALID_PROGRAM";
        case CL_INVALID_PROGRAM_EXECUTABLE: return "CL_INVALID_PROGRAM_EXECUTABLE";
        case CL_INVALID_KERNEL_NAME: return "CL_INVALID_KERNEL_NAME";
        case CL_INVALID_KERNEL: return "CL_INVALID_KERNEL";
        case CL_INVALID_ARG_INDEX: return "CL_INVALID_ARG_INDEX";
        case CL_INVALID_ARG_VALUE: return "CL_INVALID_ARG_VALUE";
        case CL_INVALID_ARG_SIZE: return "CL_INVALID_ARG_SIZE";
        case CL_INVALID_KERNEL_ARGS: return "CL_INVALID_KERNEL_ARGS";
        case CL_INVALID_WORK_DIMENSION: return "CL_INVALID_WORK_DIMENSION";
        case CL_INVALID_GLOBAL_WORK_SIZE: return "CL_INVALID_GLOBAL_WORK_SIZE";
        default: return "unknown OpenCL error";
    }
}

void set_cl_error(char *error, size_t error_size, const char *action, cl_int code) {
    char message[256];
    std::snprintf(message, sizeof(message), "%s: %s (%d)",
                  action, cl_error_name(code), static_cast<int>(code));
    gp_compute_set_error(error, error_size, message);
}

void *load_symbol(const char *name) {
#ifdef _WIN32
    return reinterpret_cast<void *>(GetProcAddress(opencl.library, name));
#else
    return dlsym(opencl.library, name);
#endif
}

void load_opencl() {
#ifdef _WIN32
    opencl.library = LoadLibraryA("OpenCL.dll");
#else
    opencl.library = dlopen("libOpenCL.so.1", RTLD_NOW | RTLD_LOCAL);
    if (opencl.library == nullptr) {
        opencl.library = dlopen("libOpenCL.so", RTLD_NOW | RTLD_LOCAL);
    }
#endif
    if (opencl.library == nullptr) {
        opencl_load_error = "OpenCL loader is not installed";
        return;
    }

#define GP_LOAD(field, symbol)                                                   \
    opencl.field = reinterpret_cast<symbol##_fn>(load_symbol(#symbol));          \
    if (opencl.field == nullptr) {                                               \
        opencl_load_error = std::string("OpenCL loader is missing ") + #symbol; \
        return;                                                                  \
    }

    GP_LOAD(get_platform_ids, clGetPlatformIDs)
    GP_LOAD(get_platform_info, clGetPlatformInfo)
    GP_LOAD(get_device_ids, clGetDeviceIDs)
    GP_LOAD(get_device_info, clGetDeviceInfo)
    GP_LOAD(create_context, clCreateContext)
    GP_LOAD(release_context, clReleaseContext)
    GP_LOAD(create_command_queue, clCreateCommandQueue)
    GP_LOAD(release_command_queue, clReleaseCommandQueue)
    GP_LOAD(create_buffer, clCreateBuffer)
    GP_LOAD(release_mem, clReleaseMemObject)
    GP_LOAD(enqueue_read, clEnqueueReadBuffer)
    GP_LOAD(enqueue_write, clEnqueueWriteBuffer)
    GP_LOAD(enqueue_fill, clEnqueueFillBuffer)
    GP_LOAD(create_program, clCreateProgramWithSource)
    GP_LOAD(build_program, clBuildProgram)
    GP_LOAD(get_program_build_info, clGetProgramBuildInfo)
    GP_LOAD(release_program, clReleaseProgram)
    GP_LOAD(create_kernel, clCreateKernel)
    GP_LOAD(release_kernel, clReleaseKernel)
    GP_LOAD(set_kernel_arg, clSetKernelArg)
    GP_LOAD(enqueue_kernel, clEnqueueNDRangeKernel)
    GP_LOAD(get_event_info, clGetEventInfo)
    GP_LOAD(wait_for_events, clWaitForEvents)
    GP_LOAD(release_event, clReleaseEvent)
    GP_LOAD(finish, clFinish)

#undef GP_LOAD
}

bool ensure_opencl(char *error, size_t error_size) {
    std::call_once(opencl_once, load_opencl);
    if (!opencl_load_error.empty()) {
        gp_compute_set_error(error, error_size, opencl_load_error.c_str());
        return false;
    }
    return true;
}

bool platforms(std::vector<cl_platform_id> *result,
               char *error, size_t error_size) {
    if (!ensure_opencl(error, error_size)) return false;
    cl_uint count = 0;
    cl_int status = opencl.get_platform_ids(0, nullptr, &count);
    if (status == -1001) {
        result->clear();
        return true;
    }
    if (status != CL_SUCCESS) {
        set_cl_error(error, error_size, "cannot enumerate OpenCL platforms", status);
        return false;
    }
    result->resize(count);
    if (count == 0) return true;
    status = opencl.get_platform_ids(count, result->data(), nullptr);
    if (status != CL_SUCCESS) {
        set_cl_error(error, error_size, "cannot read OpenCL platforms", status);
        return false;
    }
    return true;
}

bool platform_at(int32_t index, cl_platform_id *platform,
                 char *error, size_t error_size) {
    std::vector<cl_platform_id> values;
    if (!platforms(&values, error, error_size)) return false;
    if (index < 0 || static_cast<size_t>(index) >= values.size()) {
        gp_compute_set_error(error, error_size, "OpenCL platform index is outside the available range");
        return false;
    }
    *platform = values[static_cast<size_t>(index)];
    return true;
}

bool devices(cl_platform_id platform, std::vector<cl_device_id> *result,
             char *error, size_t error_size) {
    cl_uint count = 0;
    cl_int status =
        opencl.get_device_ids(platform, CL_DEVICE_TYPE_ALL, 0, nullptr, &count);
    if (status == CL_DEVICE_NOT_FOUND) {
        result->clear();
        return true;
    }
    if (status != CL_SUCCESS) {
        set_cl_error(error, error_size, "cannot enumerate OpenCL devices", status);
        return false;
    }
    result->resize(count);
    if (count == 0) return true;
    status = opencl.get_device_ids(platform, CL_DEVICE_TYPE_ALL,
                                   count, result->data(), nullptr);
    if (status != CL_SUCCESS) {
        set_cl_error(error, error_size, "cannot read OpenCL devices", status);
        return false;
    }
    return true;
}

bool device_at(int32_t platform_index, int32_t device_index,
               cl_platform_id *platform, cl_device_id *device,
               char *error, size_t error_size) {
    if (!platform_at(platform_index, platform, error, error_size)) return false;
    std::vector<cl_device_id> values;
    if (!devices(*platform, &values, error, error_size)) return false;
    if (device_index < 0 || static_cast<size_t>(device_index) >= values.size()) {
        gp_compute_set_error(error, error_size, "OpenCL device index is outside the available range");
        return false;
    }
    *device = values[static_cast<size_t>(device_index)];
    return true;
}

template <typename Id, typename Info, typename Function>
bool info_string(Id id, Info info, Function function, std::string *result,
                 char *error, size_t error_size) {
    size_t size = 0;
    cl_int status = function(id, info, 0, nullptr, &size);
    if (status != CL_SUCCESS) {
        set_cl_error(error, error_size, "cannot read OpenCL information", status);
        return false;
    }
    std::vector<char> text(std::max<size_t>(size, 1));
    status = function(id, info, text.size(), text.data(), nullptr);
    if (status != CL_SUCCESS) {
        set_cl_error(error, error_size, "cannot read OpenCL information", status);
        return false;
    }
    *result = text.data();
    return true;
}

bool read_device_fp64(cl_device_id device, bool *supported,
                      char *error, size_t error_size) {
    cl_device_fp_config config = 0;
    cl_int status = opencl.get_device_info(
        device, CL_DEVICE_DOUBLE_FP_CONFIG, sizeof(config), &config, nullptr);
    if (status == CL_SUCCESS) {
        *supported = config != 0;
        return true;
    }
    std::string extensions;
    if (!info_string(device, CL_DEVICE_EXTENSIONS, opencl.get_device_info,
                     &extensions, error, error_size)) {
        return false;
    }
    *supported = extensions.find("cl_khr_fp64") != std::string::npos;
    return true;
}

void copy_text(const std::string &source, char *value, size_t value_size) {
    if (value == nullptr || value_size == 0) return;
    const size_t count = std::min(value_size - 1, source.size());
    std::memcpy(value, source.data(), count);
    value[count] = '\0';
}

const char *kernel_source_base = R"CLC(
inline ulong gp_index(ulong i, int rank, ulong dim1,
                      ulong stride0, ulong stride1, ulong offset) {
    return rank == 1
        ? offset + i * stride0
        : offset + (i / dim1) * stride0 + (i % dim1) * stride1;
}

#define GP_KERNELS(TYPE, SUFFIX) \
__kernel void fill_##SUFFIX( \
    __global TYPE *data, ulong offset, int rank, ulong dim1, \
    ulong stride0, ulong stride1, ulong count, TYPE value) { \
    ulong i = get_global_id(0); \
    if (i < count) data[gp_index(i, rank, dim1, stride0, stride1, offset)] = value; \
} \
__kernel void copy_##SUFFIX( \
    __global TYPE *destination, ulong destination_offset, int destination_rank, \
    ulong destination_dim1, ulong destination_stride0, ulong destination_stride1, \
    __global const TYPE *source, ulong source_offset, int source_rank, \
    ulong source_dim1, ulong source_stride0, ulong source_stride1, ulong count) { \
    ulong i = get_global_id(0); \
    if (i < count) { \
        destination[gp_index(i, destination_rank, destination_dim1, \
                             destination_stride0, destination_stride1, destination_offset)] = \
            source[gp_index(i, source_rank, source_dim1, \
                            source_stride0, source_stride1, source_offset)]; \
    } \
} \
__kernel void scal_##SUFFIX( \
    __global TYPE *data, ulong offset, int rank, ulong dim1, \
    ulong stride0, ulong stride1, ulong count, TYPE alpha) { \
    ulong i = get_global_id(0); \
    if (i < count) { \
        ulong at = gp_index(i, rank, dim1, stride0, stride1, offset); \
        data[at] = alpha * data[at]; \
    } \
} \
__kernel void axpy_##SUFFIX( \
    __global TYPE *output, \
    __global const TYPE *y, ulong y_offset, int y_rank, ulong y_dim1, \
    ulong y_stride0, ulong y_stride1, TYPE alpha, \
    __global const TYPE *x, ulong x_offset, int x_rank, ulong x_dim1, \
    ulong x_stride0, ulong x_stride1, ulong count) { \
    ulong i = get_global_id(0); \
    if (i < count) { \
        output[i] = alpha * x[gp_index(i, x_rank, x_dim1, x_stride0, x_stride1, x_offset)] \
                  + y[gp_index(i, y_rank, y_dim1, y_stride0, y_stride1, y_offset)]; \
    } \
} \
__kernel void dot_##SUFFIX( \
    __global const TYPE *x, ulong x_offset, ulong x_stride, \
    __global const TYPE *y, ulong y_offset, ulong y_stride, \
    ulong count, __global TYPE *output) { \
    if (get_global_id(0) == 0) { \
        TYPE value = (TYPE) 0; \
        for (ulong i = 0; i < count; ++i) \
            value += x[x_offset + i * x_stride] * y[y_offset + i * y_stride]; \
        output[0] = value; \
    } \
} \
__kernel void mm_##SUFFIX( \
    __global const TYPE *a, ulong a_offset, ulong a_stride0, ulong a_stride1, \
    __global const TYPE *b, ulong b_offset, ulong b_stride0, ulong b_stride1, \
    ulong inner_count, __global TYPE *output, ulong columns) { \
    ulong row = get_global_id(0); \
    ulong column = get_global_id(1); \
    TYPE value = (TYPE) 0; \
    for (ulong inner = 0; inner < inner_count; ++inner) \
        value += a[a_offset + row * a_stride0 + inner * a_stride1] \
               * b[b_offset + inner * b_stride0 + column * b_stride1]; \
    output[row * columns + column] = value; \
}

GP_KERNELS(float, f32)
GP_KERNELS(int, i32)
)CLC";

const char *kernel_source_fp64 = R"CLC(
#pragma OPENCL EXTENSION cl_khr_fp64 : enable
GP_KERNELS(double, f64)
)CLC";

bool build_program(OpenClState *state, char *error, size_t error_size) {
    std::string source(kernel_source_base);
    if (state->fp64) source += kernel_source_fp64;
    const char *text = source.c_str();
    const size_t length = source.size();
    cl_int status = CL_SUCCESS;
    state->program =
        opencl.create_program(state->context, 1, &text, &length, &status);
    if (state->program == nullptr || status != CL_SUCCESS) {
        set_cl_error(error, error_size, "cannot create OpenCL program", status);
        return false;
    }
    status = opencl.build_program(state->program, 1, &state->device,
                                  "-cl-std=CL1.2", nullptr, nullptr);
    if (status == CL_SUCCESS) return true;

    size_t log_size = 0;
    opencl.get_program_build_info(state->program, state->device,
                                  CL_PROGRAM_BUILD_LOG, 0, nullptr, &log_size);
    std::vector<char> log(std::max<size_t>(log_size, 1));
    opencl.get_program_build_info(state->program, state->device,
                                  CL_PROGRAM_BUILD_LOG, log.size(), log.data(), nullptr);
    const std::string message =
        std::string("cannot build OpenCL kernels: ") + cl_error_name(status) +
        " (" + std::to_string(status) + "): " + log.data();
    gp_compute_set_error(error, error_size, message.c_str());
    return false;
}

OpenClState *state_of(const GpComputeEngine *engine) {
    return static_cast<OpenClState *>(engine->state);
}

cl_mem memory_of(const GpComputeView *view) {
    return static_cast<cl_mem>(view->storage->data);
}

struct ViewArguments {
    cl_ulong offset;
    cl_int rank;
    cl_ulong dim1;
    cl_ulong stride0;
    cl_ulong stride1;
    cl_ulong count;
};

bool view_arguments(const GpComputeView *view, ViewArguments *arguments,
                    char *error, size_t error_size) {
    if (view->shape.size() != 1 && view->shape.size() != 2) {
        gp_compute_set_error(error, error_size,
                             "OpenCL operations currently require a vector or matrix");
        return false;
    }
    arguments->offset = view->offset;
    arguments->rank = static_cast<cl_int>(view->shape.size());
    arguments->dim1 =
        view->shape.size() == 2 ? static_cast<cl_ulong>(view->shape[1]) : 1;
    arguments->stride0 = static_cast<cl_ulong>(view->strides[0]);
    arguments->stride1 =
        view->shape.size() == 2 ? static_cast<cl_ulong>(view->strides[1]) : 1;
    arguments->count = gp_compute_internal_view_count(view);
    return true;
}

template <typename T>
bool set_kernel_argument(cl_kernel kernel, cl_uint index, const T &value,
                         char *error, size_t error_size) {
    const cl_int status =
        opencl.set_kernel_arg(kernel, index, sizeof(T), &value);
    if (status != CL_SUCCESS) {
        set_cl_error(error, error_size, "cannot set OpenCL kernel argument", status);
        return false;
    }
    return true;
}

const char *kernel_name(const char *operation, int dtype) {
    if (std::strcmp(operation, "fill") == 0) {
        if (dtype == GP_COMPUTE_F32) return "fill_f32";
        if (dtype == GP_COMPUTE_F64) return "fill_f64";
        return "fill_i32";
    }
    if (std::strcmp(operation, "copy") == 0) {
        if (dtype == GP_COMPUTE_F32) return "copy_f32";
        if (dtype == GP_COMPUTE_F64) return "copy_f64";
        return "copy_i32";
    }
    if (std::strcmp(operation, "scal") == 0) {
        return dtype == GP_COMPUTE_F32 ? "scal_f32" : "scal_f64";
    }
    if (std::strcmp(operation, "axpy") == 0) {
        return dtype == GP_COMPUTE_F32 ? "axpy_f32" : "axpy_f64";
    }
    if (std::strcmp(operation, "dot") == 0) {
        return dtype == GP_COMPUTE_F32 ? "dot_f32" : "dot_f64";
    }
    return dtype == GP_COMPUTE_F32 ? "mm_f32" : "mm_f64";
}

cl_kernel create_kernel(OpenClState *state, const char *name,
                        char *error, size_t error_size) {
    cl_int status = CL_SUCCESS;
    cl_kernel kernel = opencl.create_kernel(state->program, name, &status);
    if (kernel == nullptr || status != CL_SUCCESS) {
        set_cl_error(error, error_size, "cannot create OpenCL kernel", status);
        return nullptr;
    }
    return kernel;
}

bool enqueue_1d(OpenClState *state, cl_kernel kernel, size_t count,
                char *error, size_t error_size) {
    if (count == 0) return true;
    const size_t global[1] = {count};
    const cl_int status =
        opencl.enqueue_kernel(state->queue, kernel, 1, nullptr, global,
                              nullptr, 0, nullptr, nullptr);
    if (status != CL_SUCCESS) {
        set_cl_error(error, error_size, "cannot enqueue OpenCL kernel", status);
        return false;
    }
    return true;
}

bool finish(OpenClState *state, char *error, size_t error_size) {
    const cl_int status = opencl.finish(state->queue);
    if (status != CL_SUCCESS) {
        set_cl_error(error, error_size, "cannot finish OpenCL queue", status);
        return false;
    }
    return true;
}

template <typename T>
bool convert_host_value(double value, T *result, char *error, size_t error_size) {
    *result = static_cast<T>(value);
    return true;
}

template <>
bool convert_host_value<int32_t>(double value, int32_t *result,
                                 char *error, size_t error_size) {
    if (!std::isfinite(value) || std::trunc(value) != value ||
        value < std::numeric_limits<int32_t>::min() ||
        value > std::numeric_limits<int32_t>::max()) {
        gp_compute_set_error(error, error_size, "value cannot be represented as i32");
        return false;
    }
    *result = static_cast<int32_t>(value);
    return true;
}

bool run_copy_kernel(const GpComputeView *destination,
                     const GpComputeView *source,
                     cl_mem destination_memory,
                     const ViewArguments &destination_args,
                     cl_mem source_memory,
                     const ViewArguments &source_args,
                     char *error, size_t error_size) {
    OpenClState *state = state_of(destination->storage->engine);
    cl_kernel kernel = create_kernel(
        state, kernel_name("copy", destination->storage->dtype),
        error, error_size);
    if (kernel == nullptr) return false;
    cl_uint argument = 0;
    bool ok =
        set_kernel_argument(kernel, argument++, destination_memory, error, error_size) &&
        set_kernel_argument(kernel, argument++, destination_args.offset, error, error_size) &&
        set_kernel_argument(kernel, argument++, destination_args.rank, error, error_size) &&
        set_kernel_argument(kernel, argument++, destination_args.dim1, error, error_size) &&
        set_kernel_argument(kernel, argument++, destination_args.stride0, error, error_size) &&
        set_kernel_argument(kernel, argument++, destination_args.stride1, error, error_size) &&
        set_kernel_argument(kernel, argument++, source_memory, error, error_size) &&
        set_kernel_argument(kernel, argument++, source_args.offset, error, error_size) &&
        set_kernel_argument(kernel, argument++, source_args.rank, error, error_size) &&
        set_kernel_argument(kernel, argument++, source_args.dim1, error, error_size) &&
        set_kernel_argument(kernel, argument++, source_args.stride0, error, error_size) &&
        set_kernel_argument(kernel, argument++, source_args.stride1, error, error_size) &&
        set_kernel_argument(kernel, argument++, source_args.count, error, error_size);
    if (ok) {
        ok = enqueue_1d(state, kernel, static_cast<size_t>(source_args.count),
                        error, error_size);
    }
    opencl.release_kernel(kernel);
    return ok;
}

ViewArguments contiguous_arguments(cl_ulong count) {
    return ViewArguments{0, 1, 1, 1, 1, count};
}

template <typename T>
int fill_t(GpComputeView *view, double value,
           char *error, size_t error_size) {
    T typed_value{};
    if (!convert_host_value(value, &typed_value, error, error_size)) return -1;
    ViewArguments arguments{};
    if (!view_arguments(view, &arguments, error, error_size)) return -1;
    if (arguments.count == 0) return 0;
    OpenClState *state = state_of(view->storage->engine);
    cl_kernel kernel = create_kernel(
        state, kernel_name("fill", view->storage->dtype),
        error, error_size);
    if (kernel == nullptr) return -1;
    cl_mem memory = memory_of(view);
    cl_uint argument = 0;
    bool ok =
        set_kernel_argument(kernel, argument++, memory, error, error_size) &&
        set_kernel_argument(kernel, argument++, arguments.offset, error, error_size) &&
        set_kernel_argument(kernel, argument++, arguments.rank, error, error_size) &&
        set_kernel_argument(kernel, argument++, arguments.dim1, error, error_size) &&
        set_kernel_argument(kernel, argument++, arguments.stride0, error, error_size) &&
        set_kernel_argument(kernel, argument++, arguments.stride1, error, error_size) &&
        set_kernel_argument(kernel, argument++, arguments.count, error, error_size) &&
        set_kernel_argument(kernel, argument++, typed_value, error, error_size);
    if (ok) {
        ok = enqueue_1d(state, kernel, static_cast<size_t>(arguments.count),
                        error, error_size);
    }
    opencl.release_kernel(kernel);
    return ok && finish(state, error, error_size) ? 0 : -1;
}

template <typename T>
int scal_t(GpComputeView *view, double alpha,
           char *error, size_t error_size) {
    T typed_alpha{};
    if (!convert_host_value(alpha, &typed_alpha, error, error_size)) return -1;
    ViewArguments arguments{};
    if (!view_arguments(view, &arguments, error, error_size)) return -1;
    if (arguments.count == 0) return 0;
    OpenClState *state = state_of(view->storage->engine);
    cl_kernel kernel = create_kernel(
        state, kernel_name("scal", view->storage->dtype),
        error, error_size);
    if (kernel == nullptr) return -1;
    cl_mem memory = memory_of(view);
    cl_uint argument = 0;
    bool ok =
        set_kernel_argument(kernel, argument++, memory, error, error_size) &&
        set_kernel_argument(kernel, argument++, arguments.offset, error, error_size) &&
        set_kernel_argument(kernel, argument++, arguments.rank, error, error_size) &&
        set_kernel_argument(kernel, argument++, arguments.dim1, error, error_size) &&
        set_kernel_argument(kernel, argument++, arguments.stride0, error, error_size) &&
        set_kernel_argument(kernel, argument++, arguments.stride1, error, error_size) &&
        set_kernel_argument(kernel, argument++, arguments.count, error, error_size) &&
        set_kernel_argument(kernel, argument++, typed_alpha, error, error_size);
    if (ok) {
        ok = enqueue_1d(state, kernel, static_cast<size_t>(arguments.count),
                        error, error_size);
    }
    opencl.release_kernel(kernel);
    return ok && finish(state, error, error_size) ? 0 : -1;
}

template <typename T>
int axpy_t(GpComputeView *y, double alpha, const GpComputeView *x,
           char *error, size_t error_size) {
    T typed_alpha{};
    if (!convert_host_value(alpha, &typed_alpha, error, error_size)) return -1;
    ViewArguments y_args{};
    ViewArguments x_args{};
    if (!view_arguments(y, &y_args, error, error_size) ||
        !view_arguments(x, &x_args, error, error_size)) {
        return -1;
    }
    if (x_args.count == 0) return 0;
    OpenClState *state = state_of(y->storage->engine);
    cl_int status = CL_SUCCESS;
    const size_t bytes = static_cast<size_t>(x_args.count) * sizeof(T);
    cl_mem temporary =
        opencl.create_buffer(state->context, CL_MEM_READ_WRITE, bytes,
                             nullptr, &status);
    if (temporary == nullptr || status != CL_SUCCESS) {
        set_cl_error(error, error_size, "cannot allocate OpenCL axpy temporary", status);
        return -1;
    }
    cl_kernel kernel = create_kernel(
        state, kernel_name("axpy", y->storage->dtype),
        error, error_size);
    if (kernel == nullptr) {
        opencl.release_mem(temporary);
        return -1;
    }
    cl_mem y_memory = memory_of(y);
    cl_mem x_memory = memory_of(x);
    cl_uint argument = 0;
    bool ok =
        set_kernel_argument(kernel, argument++, temporary, error, error_size) &&
        set_kernel_argument(kernel, argument++, y_memory, error, error_size) &&
        set_kernel_argument(kernel, argument++, y_args.offset, error, error_size) &&
        set_kernel_argument(kernel, argument++, y_args.rank, error, error_size) &&
        set_kernel_argument(kernel, argument++, y_args.dim1, error, error_size) &&
        set_kernel_argument(kernel, argument++, y_args.stride0, error, error_size) &&
        set_kernel_argument(kernel, argument++, y_args.stride1, error, error_size) &&
        set_kernel_argument(kernel, argument++, typed_alpha, error, error_size) &&
        set_kernel_argument(kernel, argument++, x_memory, error, error_size) &&
        set_kernel_argument(kernel, argument++, x_args.offset, error, error_size) &&
        set_kernel_argument(kernel, argument++, x_args.rank, error, error_size) &&
        set_kernel_argument(kernel, argument++, x_args.dim1, error, error_size) &&
        set_kernel_argument(kernel, argument++, x_args.stride0, error, error_size) &&
        set_kernel_argument(kernel, argument++, x_args.stride1, error, error_size) &&
        set_kernel_argument(kernel, argument++, x_args.count, error, error_size);
    if (ok) {
        ok = enqueue_1d(state, kernel, static_cast<size_t>(x_args.count),
                        error, error_size);
    }
    opencl.release_kernel(kernel);
    if (ok) {
        const ViewArguments temporary_args = contiguous_arguments(x_args.count);
        ok = run_copy_kernel(y, x, y_memory, y_args, temporary,
                             temporary_args, error, error_size);
    }
    if (ok) ok = finish(state, error, error_size);
    opencl.release_mem(temporary);
    return ok ? 0 : -1;
}

template <typename T>
int dot_t(const GpComputeView *x, const GpComputeView *y, double *result,
          char *error, size_t error_size) {
    OpenClState *state = state_of(x->storage->engine);
    cl_int status = CL_SUCCESS;
    cl_mem output =
        opencl.create_buffer(state->context, CL_MEM_READ_WRITE,
                             sizeof(T), nullptr, &status);
    if (output == nullptr || status != CL_SUCCESS) {
        set_cl_error(error, error_size, "cannot allocate OpenCL dot result", status);
        return -1;
    }
    cl_kernel kernel = create_kernel(
        state, kernel_name("dot", x->storage->dtype),
        error, error_size);
    if (kernel == nullptr) {
        opencl.release_mem(output);
        return -1;
    }
    cl_mem x_memory = memory_of(x);
    cl_mem y_memory = memory_of(y);
    const cl_ulong x_offset = x->offset;
    const cl_ulong x_stride = static_cast<cl_ulong>(x->strides[0]);
    const cl_ulong y_offset = y->offset;
    const cl_ulong y_stride = static_cast<cl_ulong>(y->strides[0]);
    const cl_ulong count = gp_compute_internal_view_count(x);
    cl_uint argument = 0;
    bool ok =
        set_kernel_argument(kernel, argument++, x_memory, error, error_size) &&
        set_kernel_argument(kernel, argument++, x_offset, error, error_size) &&
        set_kernel_argument(kernel, argument++, x_stride, error, error_size) &&
        set_kernel_argument(kernel, argument++, y_memory, error, error_size) &&
        set_kernel_argument(kernel, argument++, y_offset, error, error_size) &&
        set_kernel_argument(kernel, argument++, y_stride, error, error_size) &&
        set_kernel_argument(kernel, argument++, count, error, error_size) &&
        set_kernel_argument(kernel, argument++, output, error, error_size);
    if (ok) ok = enqueue_1d(state, kernel, 1, error, error_size);
    opencl.release_kernel(kernel);
    T value{};
    if (ok) {
        status = opencl.enqueue_read(state->queue, output, CL_TRUE, 0,
                                     sizeof(value), &value, 0, nullptr, nullptr);
        if (status != CL_SUCCESS) {
            set_cl_error(error, error_size, "cannot read OpenCL dot result", status);
            ok = false;
        }
    }
    opencl.release_mem(output);
    if (!ok) return -1;
    *result = static_cast<double>(value);
    return 0;
}

template <typename T>
GpComputeView *mm_t(const GpComputeView *a, const GpComputeView *b,
                    char *error, size_t error_size) {
    const int64_t shape[2] = {a->shape[0], b->shape[1]};
    GpComputeView *result =
        gp_compute_view_new(a->storage->engine, a->storage->dtype,
                            shape, 2, error, error_size);
    if (result == nullptr) return nullptr;
    if (shape[0] == 0 || shape[1] == 0) return result;
    OpenClState *state = state_of(a->storage->engine);
    cl_kernel kernel = create_kernel(
        state, kernel_name("mm", a->storage->dtype),
        error, error_size);
    if (kernel == nullptr) {
        gp_compute_view_free(result);
        return nullptr;
    }
    cl_mem a_memory = memory_of(a);
    cl_mem b_memory = memory_of(b);
    cl_mem result_memory = memory_of(result);
    const cl_ulong a_offset = a->offset;
    const cl_ulong a_stride0 = static_cast<cl_ulong>(a->strides[0]);
    const cl_ulong a_stride1 = static_cast<cl_ulong>(a->strides[1]);
    const cl_ulong b_offset = b->offset;
    const cl_ulong b_stride0 = static_cast<cl_ulong>(b->strides[0]);
    const cl_ulong b_stride1 = static_cast<cl_ulong>(b->strides[1]);
    const cl_ulong inner_count = static_cast<cl_ulong>(a->shape[1]);
    const cl_ulong columns = static_cast<cl_ulong>(b->shape[1]);
    cl_uint argument = 0;
    bool ok =
        set_kernel_argument(kernel, argument++, a_memory, error, error_size) &&
        set_kernel_argument(kernel, argument++, a_offset, error, error_size) &&
        set_kernel_argument(kernel, argument++, a_stride0, error, error_size) &&
        set_kernel_argument(kernel, argument++, a_stride1, error, error_size) &&
        set_kernel_argument(kernel, argument++, b_memory, error, error_size) &&
        set_kernel_argument(kernel, argument++, b_offset, error, error_size) &&
        set_kernel_argument(kernel, argument++, b_stride0, error, error_size) &&
        set_kernel_argument(kernel, argument++, b_stride1, error, error_size) &&
        set_kernel_argument(kernel, argument++, inner_count, error, error_size) &&
        set_kernel_argument(kernel, argument++, result_memory, error, error_size) &&
        set_kernel_argument(kernel, argument++, columns, error, error_size);
    if (ok) {
        const size_t global[2] = {
            static_cast<size_t>(shape[0]), static_cast<size_t>(shape[1])
        };
        const cl_int status =
            opencl.enqueue_kernel(state->queue, kernel, 2, nullptr, global,
                                  nullptr, 0, nullptr, nullptr);
        if (status != CL_SUCCESS) {
            set_cl_error(error, error_size, "cannot enqueue OpenCL matrix multiplication", status);
            ok = false;
        }
    }
    opencl.release_kernel(kernel);
    if (ok) ok = finish(state, error, error_size);
    if (!ok) {
        gp_compute_view_free(result);
        return nullptr;
    }
    return result;
}

template <typename T>
bool enqueue_fill_t(GpComputeQueue *queue, GpComputeView *view, double value,
                    GpComputeEvent *const *dependencies,
                    int32_t dependency_count, void **event_state,
                    char *error, size_t error_size) {
    T typed_value{};
    if (!convert_host_value(value, &typed_value, error, error_size)) return false;
    ViewArguments arguments{};
    if (!view_arguments(view, &arguments, error, error_size)) return false;
    std::vector<cl_event> waits;
    waits.reserve(static_cast<size_t>(dependency_count));
    for (int32_t index = 0; index < dependency_count; ++index) {
        if (dependencies[index]->state != nullptr) {
            waits.push_back(static_cast<cl_event>(dependencies[index]->state));
        }
    }
    if (arguments.count == 0) {
        if (!waits.empty()) {
            const cl_int status =
                opencl.wait_for_events(static_cast<cl_uint>(waits.size()),
                                       waits.data());
            if (status != CL_SUCCESS) {
                set_cl_error(error, error_size,
                             "cannot wait for OpenCL dependencies", status);
                return false;
            }
        }
        *event_state = nullptr;
        return true;
    }

    OpenClState *state = state_of(view->storage->engine);
    cl_kernel kernel = create_kernel(
        state, kernel_name("fill", view->storage->dtype),
        error, error_size);
    if (kernel == nullptr) return false;
    cl_mem memory = memory_of(view);
    cl_uint argument = 0;
    bool ok =
        set_kernel_argument(kernel, argument++, memory, error, error_size) &&
        set_kernel_argument(kernel, argument++, arguments.offset, error, error_size) &&
        set_kernel_argument(kernel, argument++, arguments.rank, error, error_size) &&
        set_kernel_argument(kernel, argument++, arguments.dim1, error, error_size) &&
        set_kernel_argument(kernel, argument++, arguments.stride0, error, error_size) &&
        set_kernel_argument(kernel, argument++, arguments.stride1, error, error_size) &&
        set_kernel_argument(kernel, argument++, arguments.count, error, error_size) &&
        set_kernel_argument(kernel, argument++, typed_value, error, error_size);
    cl_event event = nullptr;
    if (ok) {
        const size_t global[1] = {static_cast<size_t>(arguments.count)};
        const cl_int status =
            opencl.enqueue_kernel(
                static_cast<cl_command_queue>(queue->state), kernel, 1,
                nullptr, global, nullptr, static_cast<cl_uint>(waits.size()),
                waits.empty() ? nullptr : waits.data(), &event);
        if (status != CL_SUCCESS) {
            set_cl_error(error, error_size,
                         "cannot enqueue OpenCL fill", status);
            ok = false;
        }
    }
    opencl.release_kernel(kernel);
    if (!ok) {
        if (event != nullptr) opencl.release_event(event);
        return false;
    }
    *event_state = event;
    return true;
}

bool enqueue_copy_impl(GpComputeQueue *queue,
                       GpComputeView *destination,
                       const GpComputeView *source,
                       GpComputeEvent *const *dependencies,
                       int32_t dependency_count,
                       void **event_state,
                       char *error, size_t error_size) {
    ViewArguments destination_args{};
    ViewArguments source_args{};
    if (!view_arguments(destination, &destination_args, error, error_size) ||
        !view_arguments(source, &source_args, error, error_size)) {
        return false;
    }
    std::vector<cl_event> waits;
    waits.reserve(static_cast<size_t>(dependency_count));
    for (int32_t index = 0; index < dependency_count; ++index) {
        if (dependencies[index]->state != nullptr) {
            waits.push_back(static_cast<cl_event>(dependencies[index]->state));
        }
    }
    if (source_args.count == 0) {
        if (!waits.empty()) {
            const cl_int status =
                opencl.wait_for_events(static_cast<cl_uint>(waits.size()),
                                       waits.data());
            if (status != CL_SUCCESS) {
                set_cl_error(error, error_size,
                             "cannot wait for OpenCL dependencies", status);
                return false;
            }
        }
        *event_state = nullptr;
        return true;
    }

    OpenClState *state = state_of(queue->engine);
    const size_t width = gp_compute_dtype_size(destination->storage->dtype);
    const size_t bytes = static_cast<size_t>(source_args.count) * width;
    cl_int status = CL_SUCCESS;
    cl_mem temporary =
        opencl.create_buffer(state->context, CL_MEM_READ_WRITE,
                             bytes, nullptr, &status);
    if (temporary == nullptr || status != CL_SUCCESS) {
        set_cl_error(error, error_size,
                     "cannot allocate OpenCL copy temporary", status);
        return false;
    }
    const ViewArguments temporary_args =
        contiguous_arguments(source_args.count);
    const cl_command_queue native_queue =
        static_cast<cl_command_queue>(queue->state);

    auto enqueue_copy =
        [&](cl_mem destination_memory, const ViewArguments &to,
            cl_mem source_memory, const ViewArguments &from,
            cl_uint wait_count, const cl_event *wait_list,
            cl_event *event) -> bool {
        cl_kernel kernel = create_kernel(
            state, kernel_name("copy", destination->storage->dtype),
            error, error_size);
        if (kernel == nullptr) return false;
        cl_uint argument = 0;
        bool ok =
            set_kernel_argument(kernel, argument++, destination_memory, error, error_size) &&
            set_kernel_argument(kernel, argument++, to.offset, error, error_size) &&
            set_kernel_argument(kernel, argument++, to.rank, error, error_size) &&
            set_kernel_argument(kernel, argument++, to.dim1, error, error_size) &&
            set_kernel_argument(kernel, argument++, to.stride0, error, error_size) &&
            set_kernel_argument(kernel, argument++, to.stride1, error, error_size) &&
            set_kernel_argument(kernel, argument++, source_memory, error, error_size) &&
            set_kernel_argument(kernel, argument++, from.offset, error, error_size) &&
            set_kernel_argument(kernel, argument++, from.rank, error, error_size) &&
            set_kernel_argument(kernel, argument++, from.dim1, error, error_size) &&
            set_kernel_argument(kernel, argument++, from.stride0, error, error_size) &&
            set_kernel_argument(kernel, argument++, from.stride1, error, error_size) &&
            set_kernel_argument(kernel, argument++, from.count, error, error_size);
        if (ok) {
            const size_t global[1] = {
                static_cast<size_t>(from.count)
            };
            status = opencl.enqueue_kernel(
                native_queue, kernel, 1, nullptr, global, nullptr,
                wait_count, wait_list,
                event);
            if (status != CL_SUCCESS) {
                set_cl_error(error, error_size,
                             "cannot enqueue OpenCL copy", status);
                ok = false;
            }
        }
        opencl.release_kernel(kernel);
        return ok;
    };

    cl_event packed = nullptr;
    bool ok = enqueue_copy(
        temporary, temporary_args, memory_of(source), source_args,
        static_cast<cl_uint>(waits.size()),
        waits.empty() ? nullptr : waits.data(), &packed);
    cl_event copied = nullptr;
    if (ok) {
        ok = enqueue_copy(
            memory_of(destination), destination_args,
            temporary, temporary_args, 1, &packed, &copied);
    }
    if (packed != nullptr) opencl.release_event(packed);
    opencl.release_mem(temporary);
    if (!ok) {
        if (copied != nullptr) opencl.release_event(copied);
        return false;
    }
    *event_state = copied;
    return true;
}

template <typename Return, typename Function>
Return guard_opencl(Function &&function, Return failure,
                    char *error, size_t error_size,
                    const char *message) noexcept {
    try {
        return function();
    } catch (...) {
        gp_compute_set_error(error, error_size, message);
        return failure;
    }
}

}  // namespace

extern "C" int gp_compute_opencl_platform_count(char *error, size_t error_size) {
    return guard_opencl<int>(
        [&]() -> int {
            std::vector<cl_platform_id> values;
            if (!platforms(&values, error, error_size)) return -1;
            if (values.size() >
                static_cast<size_t>(std::numeric_limits<int>::max())) {
                gp_compute_set_error(error, error_size,
                                     "too many OpenCL platforms");
                return -1;
            }
            return static_cast<int>(values.size());
        },
        -1, error, error_size,
        "unexpected failure while enumerating OpenCL platforms");
}

extern "C" int gp_compute_opencl_platform_name(
    int32_t platform_index, char *value, size_t value_size,
    char *error, size_t error_size) {
    return guard_opencl<int>(
        [&]() -> int {
            cl_platform_id platform = nullptr;
            if (!platform_at(platform_index, &platform, error, error_size)) {
                return -1;
            }
            std::string text;
            if (!info_string(platform, CL_PLATFORM_NAME,
                             opencl.get_platform_info,
                             &text, error, error_size)) {
                return -1;
            }
            copy_text(text, value, value_size);
            return 0;
        },
        -1, error, error_size,
        "unexpected failure while reading OpenCL platform");
}

extern "C" int gp_compute_opencl_device_count(
    int32_t platform_index, char *error, size_t error_size) {
    return guard_opencl<int>(
        [&]() -> int {
            cl_platform_id platform = nullptr;
            if (!platform_at(platform_index, &platform, error, error_size)) {
                return -1;
            }
            std::vector<cl_device_id> values;
            if (!devices(platform, &values, error, error_size)) return -1;
            if (values.size() >
                static_cast<size_t>(std::numeric_limits<int>::max())) {
                gp_compute_set_error(error, error_size,
                                     "too many OpenCL devices");
                return -1;
            }
            return static_cast<int>(values.size());
        },
        -1, error, error_size,
        "unexpected failure while enumerating OpenCL devices");
}

static int opencl_device_text(
    int32_t platform_index, int32_t device_index, cl_device_info info,
    char *value, size_t value_size, char *error, size_t error_size) {
    return guard_opencl<int>(
        [&]() -> int {
            cl_platform_id platform = nullptr;
            cl_device_id device = nullptr;
            if (!device_at(platform_index, device_index, &platform, &device,
                           error, error_size)) {
                return -1;
            }
            std::string text;
            if (!info_string(device, info, opencl.get_device_info,
                             &text, error, error_size)) {
                return -1;
            }
            copy_text(text, value, value_size);
            return 0;
        },
        -1, error, error_size,
        "unexpected failure while reading OpenCL device");
}

extern "C" int gp_compute_opencl_device_name(
    int32_t platform_index, int32_t device_index,
    char *value, size_t value_size, char *error, size_t error_size) {
    return opencl_device_text(platform_index, device_index, CL_DEVICE_NAME,
                              value, value_size, error, error_size);
}

extern "C" int gp_compute_opencl_device_vendor(
    int32_t platform_index, int32_t device_index,
    char *value, size_t value_size, char *error, size_t error_size) {
    return opencl_device_text(platform_index, device_index, CL_DEVICE_VENDOR,
                              value, value_size, error, error_size);
}

extern "C" int gp_compute_opencl_device_version(
    int32_t platform_index, int32_t device_index,
    char *value, size_t value_size, char *error, size_t error_size) {
    return opencl_device_text(platform_index, device_index, CL_DEVICE_VERSION,
                              value, value_size, error, error_size);
}

extern "C" int gp_compute_opencl_device_fp64(
    int32_t platform_index, int32_t device_index,
    char *error, size_t error_size) {
    return guard_opencl<int>(
        [&]() -> int {
            cl_platform_id platform = nullptr;
            cl_device_id device = nullptr;
            if (!device_at(platform_index, device_index, &platform, &device,
                           error, error_size)) {
                return -1;
            }
            bool supported = false;
            if (!read_device_fp64(
                    device, &supported, error, error_size)) {
                return -1;
            }
            return supported ? 1 : 0;
        },
        -1, error, error_size,
        "unexpected failure while reading OpenCL fp64 capability");
}

extern "C" double gp_compute_opencl_device_global_memory(
    int32_t platform_index, int32_t device_index,
    char *error, size_t error_size) {
    return guard_opencl<double>(
        [&]() -> double {
            cl_platform_id platform = nullptr;
            cl_device_id device = nullptr;
            if (!device_at(platform_index, device_index, &platform, &device,
                           error, error_size)) {
                return -1;
            }
            cl_ulong bytes = 0;
            const cl_int status =
                opencl.get_device_info(device, CL_DEVICE_GLOBAL_MEM_SIZE,
                                       sizeof(bytes), &bytes, nullptr);
            if (status != CL_SUCCESS) {
                set_cl_error(error, error_size,
                             "cannot read OpenCL global memory", status);
                return -1;
            }
            return static_cast<double>(bytes);
        },
        -1.0, error, error_size,
        "unexpected failure while reading OpenCL memory");
}

extern "C" GpComputeEngine *gp_compute_opencl_engine_new(
    int32_t platform_index, int32_t device_index,
    char *error, size_t error_size) {
    return guard_opencl<GpComputeEngine *>(
        [&]() -> GpComputeEngine * {
            cl_platform_id platform = nullptr;
            cl_device_id device = nullptr;
            if (!device_at(platform_index, device_index, &platform, &device,
                           error, error_size)) {
                return nullptr;
            }
            auto state = std::make_unique<OpenClState>();
            state->platform = platform;
            state->device = device;
            if (!info_string(device, CL_DEVICE_NAME, opencl.get_device_info,
                             &state->device_name, error, error_size)) {
                return nullptr;
            }
            if (!read_device_fp64(
                    device, &state->fp64, error, error_size)) {
                return nullptr;
            }
            const cl_context_properties properties[] = {
                CL_CONTEXT_PLATFORM,
                reinterpret_cast<cl_context_properties>(platform),
                0
            };
            cl_int status = CL_SUCCESS;
            state->context =
                opencl.create_context(properties, 1, &device,
                                      nullptr, nullptr, &status);
            if (state->context == nullptr || status != CL_SUCCESS) {
                set_cl_error(error, error_size,
                             "cannot create OpenCL context", status);
                return nullptr;
            }
            state->queue =
                opencl.create_command_queue(
                    state->context, device, 0, &status);
            if (state->queue == nullptr || status != CL_SUCCESS) {
                set_cl_error(error, error_size,
                             "cannot create OpenCL command queue", status);
                opencl.release_context(state->context);
                state->context = nullptr;
                return nullptr;
            }
            if (!build_program(state.get(), error, error_size)) {
                if (state->program != nullptr) {
                    opencl.release_program(state->program);
                    state->program = nullptr;
                }
                opencl.release_command_queue(state->queue);
                opencl.release_context(state->context);
                state->queue = nullptr;
                state->context = nullptr;
                return nullptr;
            }

            auto engine = std::unique_ptr<GpComputeEngine>(
                new (std::nothrow) GpComputeEngine());
            if (!engine) {
                opencl.release_program(state->program);
                opencl.release_command_queue(state->queue);
                opencl.release_context(state->context);
                state->program = nullptr;
                state->queue = nullptr;
                state->context = nullptr;
                gp_compute_set_error(
                    error, error_size,
                    "out of memory while creating OpenCL engine");
                return nullptr;
            }
            engine->kind = GP_COMPUTE_ENGINE_OPENCL;
            engine->name = "opencl";
            engine->state = state.get();
            engine->device_name = state->device_name.c_str();
            state.release();
            return engine.release();
        },
        nullptr, error, error_size,
        "unexpected failure while creating OpenCL engine");
}

bool gp_opencl_storage_allocate(GpComputeEngine *engine, int dtype, uint64_t count,
                                void **data, char *error, size_t error_size) {
    OpenClState *state = state_of(engine);
    if (dtype == GP_COMPUTE_F64 && !state->fp64) {
        gp_compute_set_error(error, error_size, "OpenCL device does not support :f64");
        return false;
    }
    const size_t width = gp_compute_dtype_size(dtype);
    if (width == 0 || count > std::numeric_limits<size_t>::max() / width) {
        gp_compute_set_error(error, error_size, "OpenCL allocation is too large");
        return false;
    }
    const size_t bytes = std::max<size_t>(width, static_cast<size_t>(count) * width);
    cl_int status = CL_SUCCESS;
    cl_mem memory =
        opencl.create_buffer(state->context, CL_MEM_READ_WRITE,
                             bytes, nullptr, &status);
    if (memory == nullptr || status != CL_SUCCESS) {
        set_cl_error(error, error_size, "cannot allocate OpenCL buffer", status);
        return false;
    }
    const uint64_t zero = 0;
    status = opencl.enqueue_fill(state->queue, memory, &zero, width,
                                 0, bytes, 0, nullptr, nullptr);
    if (status == CL_SUCCESS) status = opencl.finish(state->queue);
    if (status != CL_SUCCESS) {
        opencl.release_mem(memory);
        set_cl_error(error, error_size, "cannot initialize OpenCL buffer", status);
        return false;
    }
    *data = memory;
    return true;
}

void gp_opencl_storage_free(GpComputeEngine *, void *data) {
    if (data != nullptr) opencl.release_mem(static_cast<cl_mem>(data));
}

void gp_opencl_engine_destroy(GpComputeEngine *engine) {
    OpenClState *state = state_of(engine);
    if (state == nullptr) return;
    delete state;
    engine->state = nullptr;
    engine->device_name = "";
}

bool gp_opencl_read(const GpComputeView *view, uint64_t index, double *value,
                    char *error, size_t error_size) {
    OpenClState *state = state_of(view->storage->engine);
    const size_t width = gp_compute_dtype_size(view->storage->dtype);
    const size_t offset =
        static_cast<size_t>(gp_compute_internal_storage_offset(view, index)) * width;
    cl_int status = CL_SUCCESS;
    switch (view->storage->dtype) {
        case GP_COMPUTE_F32: {
            float result = 0;
            status = opencl.enqueue_read(state->queue, memory_of(view), CL_TRUE,
                                         offset, sizeof(result), &result,
                                         0, nullptr, nullptr);
            *value = result;
            break;
        }
        case GP_COMPUTE_F64: {
            double result = 0;
            status = opencl.enqueue_read(state->queue, memory_of(view), CL_TRUE,
                                         offset, sizeof(result), &result,
                                         0, nullptr, nullptr);
            *value = result;
            break;
        }
        case GP_COMPUTE_I32: {
            int32_t result = 0;
            status = opencl.enqueue_read(state->queue, memory_of(view), CL_TRUE,
                                         offset, sizeof(result), &result,
                                         0, nullptr, nullptr);
            *value = result;
            break;
        }
        default:
            gp_compute_set_error(error, error_size, "unsupported OpenCL dtype");
            return false;
    }
    if (status != CL_SUCCESS) {
        set_cl_error(error, error_size, "cannot read OpenCL buffer", status);
        return false;
    }
    return true;
}

bool gp_opencl_write(GpComputeView *view, uint64_t index, double value,
                     char *error, size_t error_size) {
    OpenClState *state = state_of(view->storage->engine);
    const size_t width = gp_compute_dtype_size(view->storage->dtype);
    const size_t offset =
        static_cast<size_t>(gp_compute_internal_storage_offset(view, index)) * width;
    cl_int status = CL_SUCCESS;
    if (view->storage->dtype == GP_COMPUTE_F32) {
        float typed{};
        convert_host_value(value, &typed, error, error_size);
        status = opencl.enqueue_write(state->queue, memory_of(view), CL_TRUE,
                                      offset, sizeof(typed), &typed,
                                      0, nullptr, nullptr);
    } else if (view->storage->dtype == GP_COMPUTE_F64) {
        double typed{};
        convert_host_value(value, &typed, error, error_size);
        status = opencl.enqueue_write(state->queue, memory_of(view), CL_TRUE,
                                      offset, sizeof(typed), &typed,
                                      0, nullptr, nullptr);
    } else if (view->storage->dtype == GP_COMPUTE_I32) {
        int32_t typed{};
        if (!convert_host_value(value, &typed, error, error_size)) return false;
        status = opencl.enqueue_write(state->queue, memory_of(view), CL_TRUE,
                                      offset, sizeof(typed), &typed,
                                      0, nullptr, nullptr);
    } else {
        gp_compute_set_error(error, error_size, "unsupported OpenCL dtype");
        return false;
    }
    if (status != CL_SUCCESS) {
        set_cl_error(error, error_size, "cannot write OpenCL buffer", status);
        return false;
    }
    return true;
}

int gp_opencl_fill(GpComputeView *view, double value,
                   char *error, size_t error_size) {
    switch (view->storage->dtype) {
        case GP_COMPUTE_F32: return fill_t<float>(view, value, error, error_size);
        case GP_COMPUTE_F64: return fill_t<double>(view, value, error, error_size);
        case GP_COMPUTE_I32: return fill_t<int32_t>(view, value, error, error_size);
        default:
            gp_compute_set_error(error, error_size, "unsupported OpenCL dtype");
            return -1;
    }
}

int gp_opencl_copy(GpComputeView *destination, const GpComputeView *source,
                   char *error, size_t error_size) {
    ViewArguments destination_args{};
    ViewArguments source_args{};
    if (!view_arguments(destination, &destination_args, error, error_size) ||
        !view_arguments(source, &source_args, error, error_size)) {
        return -1;
    }
    if (source_args.count == 0) return 0;
    OpenClState *state = state_of(destination->storage->engine);
    const size_t width = gp_compute_dtype_size(destination->storage->dtype);
    const size_t bytes = static_cast<size_t>(source_args.count) * width;
    cl_int status = CL_SUCCESS;
    cl_mem temporary =
        opencl.create_buffer(state->context, CL_MEM_READ_WRITE,
                             bytes, nullptr, &status);
    if (temporary == nullptr || status != CL_SUCCESS) {
        set_cl_error(error, error_size, "cannot allocate OpenCL copy temporary", status);
        return -1;
    }
    const ViewArguments temporary_args = contiguous_arguments(source_args.count);
    bool ok = run_copy_kernel(destination, source, temporary, temporary_args,
                              memory_of(source), source_args, error, error_size);
    if (ok) {
        ok = run_copy_kernel(destination, source, memory_of(destination),
                             destination_args, temporary, temporary_args,
                             error, error_size);
    }
    if (ok) ok = finish(state, error, error_size);
    opencl.release_mem(temporary);
    return ok ? 0 : -1;
}

int gp_opencl_scal(GpComputeView *view, double alpha,
                   char *error, size_t error_size) {
    if (view->storage->dtype == GP_COMPUTE_I32) {
        gp_compute_set_error(error, error_size,
                             "OpenCL scal does not yet support :i32");
        return -1;
    }
    return view->storage->dtype == GP_COMPUTE_F32
        ? scal_t<float>(view, alpha, error, error_size)
        : scal_t<double>(view, alpha, error, error_size);
}

int gp_opencl_axpy(GpComputeView *y, double alpha, const GpComputeView *x,
                   char *error, size_t error_size) {
    if (y->storage->dtype == GP_COMPUTE_I32) {
        gp_compute_set_error(error, error_size,
                             "OpenCL axpy does not yet support :i32");
        return -1;
    }
    return y->storage->dtype == GP_COMPUTE_F32
        ? axpy_t<float>(y, alpha, x, error, error_size)
        : axpy_t<double>(y, alpha, x, error, error_size);
}

int gp_opencl_dot(const GpComputeView *x, const GpComputeView *y,
                  double *result, char *error, size_t error_size) {
    if (x->storage->dtype == GP_COMPUTE_I32) {
        gp_compute_set_error(error, error_size,
                             "OpenCL dot does not yet support :i32");
        return -1;
    }
    return x->storage->dtype == GP_COMPUTE_F32
        ? dot_t<float>(x, y, result, error, error_size)
        : dot_t<double>(x, y, result, error, error_size);
}

GpComputeView *gp_opencl_mm(const GpComputeView *a, const GpComputeView *b,
                           char *error, size_t error_size) {
    if (a->storage->dtype == GP_COMPUTE_I32) {
        gp_compute_set_error(error, error_size,
                             "OpenCL mm does not yet support :i32");
        return nullptr;
    }
    return a->storage->dtype == GP_COMPUTE_F32
        ? mm_t<float>(a, b, error, error_size)
        : mm_t<double>(a, b, error, error_size);
}

int gp_opencl_sync(GpComputeEngine *engine, char *error, size_t error_size) {
    return finish(state_of(engine), error, error_size) ? 0 : -1;
}

bool gp_opencl_queue_new(GpComputeEngine *engine, void **queue_state,
                         char *error, size_t error_size) {
    OpenClState *state = state_of(engine);
    cl_int status = CL_SUCCESS;
    cl_command_queue queue =
        opencl.create_command_queue(state->context, state->device, 0, &status);
    if (queue == nullptr || status != CL_SUCCESS) {
        set_cl_error(error, error_size, "cannot create OpenCL command queue", status);
        return false;
    }
    *queue_state = queue;
    return true;
}

void gp_opencl_queue_free(void *queue_state) {
    if (queue_state != nullptr) {
        opencl.release_command_queue(static_cast<cl_command_queue>(queue_state));
    }
}

int gp_opencl_queue_finish(void *queue_state,
                           char *error, size_t error_size) {
    const cl_int status =
        opencl.finish(static_cast<cl_command_queue>(queue_state));
    if (status != CL_SUCCESS) {
        set_cl_error(error, error_size, "cannot finish OpenCL queue", status);
        return -1;
    }
    return 0;
}

void gp_opencl_event_free(void *event_state) {
    if (event_state != nullptr) {
        opencl.release_event(static_cast<cl_event>(event_state));
    }
}

int gp_opencl_event_wait(void *event_state,
                         char *error, size_t error_size) {
    if (event_state == nullptr) return 0;
    const cl_event event = static_cast<cl_event>(event_state);
    const cl_int status = opencl.wait_for_events(1, &event);
    if (status != CL_SUCCESS) {
        set_cl_error(error, error_size, "cannot wait for OpenCL event", status);
        return -1;
    }
    return 0;
}

int gp_opencl_event_complete(void *event_state,
                             char *error, size_t error_size) {
    if (event_state == nullptr) return 1;
    cl_int execution = 0;
    const cl_int status =
        opencl.get_event_info(static_cast<cl_event>(event_state),
                              CL_EVENT_COMMAND_EXECUTION_STATUS,
                              sizeof(execution), &execution, nullptr);
    if (status != CL_SUCCESS) {
        set_cl_error(error, error_size, "cannot inspect OpenCL event", status);
        return -1;
    }
    if (execution < 0) {
        set_cl_error(error, error_size, "OpenCL command failed", execution);
        return -1;
    }
    return execution == CL_COMPLETE ? 1 : 0;
}

bool gp_opencl_enqueue_fill(GpComputeQueue *queue, GpComputeView *view,
                            double value,
                            GpComputeEvent *const *dependencies,
                            int32_t dependency_count,
                            void **event_state,
                            char *error, size_t error_size) {
    return guard_opencl<bool>(
        [&]() -> bool {
            switch (view->storage->dtype) {
                case GP_COMPUTE_F32:
                    return enqueue_fill_t<float>(
                        queue, view, value, dependencies, dependency_count,
                        event_state, error, error_size);
                case GP_COMPUTE_F64:
                    return enqueue_fill_t<double>(
                        queue, view, value, dependencies, dependency_count,
                        event_state, error, error_size);
                case GP_COMPUTE_I32:
                    return enqueue_fill_t<int32_t>(
                        queue, view, value, dependencies, dependency_count,
                        event_state, error, error_size);
                default:
                    gp_compute_set_error(
                        error, error_size, "unsupported OpenCL dtype");
                    return false;
            }
        },
        false, error, error_size,
        "unexpected failure while enqueueing OpenCL fill");
}

bool gp_opencl_enqueue_copy(GpComputeQueue *queue,
                            GpComputeView *destination,
                            const GpComputeView *source,
                            GpComputeEvent *const *dependencies,
                            int32_t dependency_count,
                            void **event_state,
                            char *error, size_t error_size) {
    return guard_opencl<bool>(
        [&]() -> bool {
            return enqueue_copy_impl(
                queue, destination, source,
                dependencies, dependency_count,
                event_state, error, error_size);
        },
        false, error, error_size,
        "unexpected failure while enqueueing OpenCL copy");
}
