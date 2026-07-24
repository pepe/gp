#ifndef GP_COMPUTE_INTERNAL_HPP
#define GP_COMPUTE_INTERNAL_HPP

#include "compute-helper.h"

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <vector>

enum GpComputeEngineKind {
    GP_COMPUTE_ENGINE_CPP = 1,
    GP_COMPUTE_ENGINE_OPENCL = 2,
};

struct GpComputeEngine {
    std::atomic<size_t> references{1};
    int kind = 0;
    const char *name = "";
    const char *device_name = "";
    void *state = nullptr;
    bool immortal = false;
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

struct GpComputeQueue {
    GpComputeEngine *engine = nullptr;
    void *state = nullptr;
};

struct GpComputeEvent {
    GpComputeEngine *engine = nullptr;
    void *state = nullptr;
    bool complete = false;
};

struct GpComputeKernel {
    GpComputeEngine *engine = nullptr;
    void *state = nullptr;
};

void gp_compute_set_error(char *error, size_t error_size, const char *message);
size_t gp_compute_dtype_size(int dtype);
uint64_t gp_compute_internal_view_count(const GpComputeView *view);
uint64_t gp_compute_internal_storage_offset(const GpComputeView *view, uint64_t index);

bool gp_opencl_storage_allocate(GpComputeEngine *engine, int dtype, uint64_t count,
                                void **data, char *error, size_t error_size);
void gp_opencl_storage_free(GpComputeEngine *engine, void *data);
void gp_opencl_engine_destroy(GpComputeEngine *engine);

bool gp_opencl_read(const GpComputeView *view, uint64_t index, double *value,
                    char *error, size_t error_size);
bool gp_opencl_write(GpComputeView *view, uint64_t index, double value,
                     char *error, size_t error_size);
int gp_opencl_fill(GpComputeView *view, double value,
                   char *error, size_t error_size);
int gp_opencl_copy(GpComputeView *destination, const GpComputeView *source,
                   char *error, size_t error_size);
int gp_opencl_scal(GpComputeView *view, double alpha,
                   char *error, size_t error_size);
int gp_opencl_axpy(GpComputeView *y, double alpha, const GpComputeView *x,
                   char *error, size_t error_size);
int gp_opencl_dot(const GpComputeView *x, const GpComputeView *y,
                  double *result, char *error, size_t error_size);
GpComputeView *gp_opencl_mm(const GpComputeView *a, const GpComputeView *b,
                           char *error, size_t error_size);
int gp_opencl_sync(GpComputeEngine *engine, char *error, size_t error_size);
bool gp_opencl_queue_new(GpComputeEngine *engine, void **state,
                         char *error, size_t error_size);
void gp_opencl_queue_free(void *state);
int gp_opencl_queue_finish(void *state, char *error, size_t error_size);
void gp_opencl_event_free(void *state);
int gp_opencl_event_wait(void *state, char *error, size_t error_size);
int gp_opencl_event_complete(void *state, char *error, size_t error_size);
bool gp_opencl_enqueue_fill(GpComputeQueue *queue, GpComputeView *view,
                            double value,
                            GpComputeEvent *const *dependencies,
                            int32_t dependency_count,
                            void **event_state,
                            char *error, size_t error_size);
bool gp_opencl_enqueue_copy(GpComputeQueue *queue,
                            GpComputeView *destination,
                            const GpComputeView *source,
                            GpComputeEvent *const *dependencies,
                            int32_t dependency_count,
                            void **event_state,
                            char *error, size_t error_size);
bool gp_opencl_enqueue_scal(GpComputeQueue *queue, GpComputeView *view,
                            double alpha,
                            GpComputeEvent *const *dependencies,
                            int32_t dependency_count,
                            void **event_state,
                            char *error, size_t error_size);
bool gp_opencl_enqueue_axpy(GpComputeQueue *queue, GpComputeView *y,
                            double alpha, const GpComputeView *x,
                            GpComputeEvent *const *dependencies,
                            int32_t dependency_count,
                            void **event_state,
                            char *error, size_t error_size);
bool gp_opencl_enqueue_dot(GpComputeQueue *queue,
                           const GpComputeView *x,
                           const GpComputeView *y,
                           GpComputeView *result,
                           GpComputeEvent *const *dependencies,
                           int32_t dependency_count,
                           void **event_state,
                           char *error, size_t error_size);
bool gp_opencl_enqueue_mm(GpComputeQueue *queue,
                          const GpComputeView *a,
                          const GpComputeView *b,
                          GpComputeView *result,
                          GpComputeEvent *const *dependencies,
                          int32_t dependency_count,
                          void **event_state,
                          char *error, size_t error_size);
bool gp_opencl_kernel_new(GpComputeEngine *engine, const char *name,
                          const char *source, size_t source_length,
                          void **kernel_state,
                          char *error, size_t error_size);
void gp_opencl_kernel_free(void *kernel_state);
bool gp_opencl_enqueue_kernel(
    GpComputeQueue *queue, void *kernel_state,
    const uint64_t *global_sizes, int32_t work_dimension,
    const GpComputeKernelArgument *arguments, int32_t argument_count,
    GpComputeEvent *const *dependencies, int32_t dependency_count,
    void **event_state, char *error, size_t error_size);

#endif
