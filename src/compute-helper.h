#ifndef GP_COMPUTE_HELPER_H
#define GP_COMPUTE_HELPER_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct GpComputeEngine GpComputeEngine;
typedef struct GpComputeView GpComputeView;
typedef struct GpComputeQueue GpComputeQueue;
typedef struct GpComputeEvent GpComputeEvent;
typedef struct GpComputeKernel GpComputeKernel;

enum GpComputeDType {
    GP_COMPUTE_F32 = 1,
    GP_COMPUTE_F64 = 2,
    GP_COMPUTE_I32 = 3,
};

enum GpComputeKernelArgumentKind {
    GP_COMPUTE_KERNEL_VIEW = 1,
    GP_COMPUTE_KERNEL_I32 = 2,
    GP_COMPUTE_KERNEL_F32 = 3,
    GP_COMPUTE_KERNEL_F64 = 4,
};

typedef struct GpComputeKernelArgument {
    int32_t kind;
    GpComputeView *view;
    double scalar;
} GpComputeKernelArgument;

GpComputeEngine *gp_compute_cpp_engine(void);
void gp_compute_engine_retain(GpComputeEngine *engine);
void gp_compute_engine_free(GpComputeEngine *engine);
const char *gp_compute_engine_name(const GpComputeEngine *engine);
const char *gp_compute_engine_device_name(const GpComputeEngine *engine);
int gp_compute_engine_sync(GpComputeEngine *engine,
                           char *error, size_t error_size);

int gp_compute_opencl_platform_count(char *error, size_t error_size);
int gp_compute_opencl_platform_name(int32_t platform_index,
                                    char *value, size_t value_size,
                                    char *error, size_t error_size);
int gp_compute_opencl_device_count(int32_t platform_index,
                                  char *error, size_t error_size);
int gp_compute_opencl_device_name(int32_t platform_index, int32_t device_index,
                                  char *value, size_t value_size,
                                  char *error, size_t error_size);
int gp_compute_opencl_device_vendor(int32_t platform_index, int32_t device_index,
                                    char *value, size_t value_size,
                                    char *error, size_t error_size);
int gp_compute_opencl_device_version(int32_t platform_index, int32_t device_index,
                                     char *value, size_t value_size,
                                     char *error, size_t error_size);
int gp_compute_opencl_device_fp64(int32_t platform_index, int32_t device_index,
                                  char *error, size_t error_size);
double gp_compute_opencl_device_global_memory(int32_t platform_index,
                                              int32_t device_index,
                                              char *error, size_t error_size);
GpComputeEngine *gp_compute_opencl_engine_new(int32_t platform_index,
                                              int32_t device_index,
                                              char *error, size_t error_size);

GpComputeView *gp_compute_view_new(GpComputeEngine *engine, int dtype,
                                   const int64_t *shape, int32_t rank,
                                   char *error, size_t error_size);
GpComputeView *gp_compute_view_slice(const GpComputeView *view,
                                     int64_t start, int64_t length,
                                     char *error, size_t error_size);
GpComputeView *gp_compute_view_row(const GpComputeView *view, int64_t row,
                                   char *error, size_t error_size);
GpComputeView *gp_compute_view_transpose(const GpComputeView *view,
                                         char *error, size_t error_size);
void gp_compute_view_free(GpComputeView *view);

int gp_compute_view_dtype(const GpComputeView *view);
int32_t gp_compute_view_rank(const GpComputeView *view);
int64_t gp_compute_view_shape(const GpComputeView *view, int32_t axis);
int64_t gp_compute_view_stride(const GpComputeView *view, int32_t axis);
uint64_t gp_compute_view_count(const GpComputeView *view);
uintptr_t gp_compute_view_storage_id(const GpComputeView *view);
GpComputeEngine *gp_compute_view_engine(const GpComputeView *view);

int gp_compute_view_get(const GpComputeView *view, uint64_t index,
                        double *value, char *error, size_t error_size);
int gp_compute_view_set(GpComputeView *view, uint64_t index, double value,
                        char *error, size_t error_size);

int gp_compute_fill(GpComputeView *view, double value,
                    char *error, size_t error_size);
int gp_compute_copy(GpComputeView *destination, const GpComputeView *source,
                    char *error, size_t error_size);
int gp_compute_scal(GpComputeView *view, double alpha,
                    char *error, size_t error_size);
int gp_compute_axpy(GpComputeView *y, double alpha, const GpComputeView *x,
                    char *error, size_t error_size);
int gp_compute_dot(const GpComputeView *x, const GpComputeView *y,
                   double *result, char *error, size_t error_size);
GpComputeView *gp_compute_mm(const GpComputeView *a, const GpComputeView *b,
                            char *error, size_t error_size);
GpComputeView *gp_compute_transfer(GpComputeEngine *engine,
                                   const GpComputeView *source,
                                   char *error, size_t error_size);

GpComputeQueue *gp_compute_queue_new(GpComputeEngine *engine,
                                     char *error, size_t error_size);
void gp_compute_queue_free(GpComputeQueue *queue);
GpComputeEngine *gp_compute_queue_engine(const GpComputeQueue *queue);
int gp_compute_queue_finish(GpComputeQueue *queue,
                            char *error, size_t error_size);

void gp_compute_event_free(GpComputeEvent *event);
GpComputeEngine *gp_compute_event_engine(const GpComputeEvent *event);
int gp_compute_event_wait(GpComputeEvent *event,
                          char *error, size_t error_size);
int gp_compute_event_complete(GpComputeEvent *event,
                              char *error, size_t error_size);

GpComputeEvent *gp_compute_enqueue_fill(
    GpComputeQueue *queue, GpComputeView *view, double value,
    GpComputeEvent *const *dependencies, int32_t dependency_count,
    char *error, size_t error_size);
GpComputeEvent *gp_compute_enqueue_copy(
    GpComputeQueue *queue, GpComputeView *destination,
    const GpComputeView *source,
    GpComputeEvent *const *dependencies, int32_t dependency_count,
    char *error, size_t error_size);
GpComputeEvent *gp_compute_enqueue_scal(
    GpComputeQueue *queue, GpComputeView *view, double alpha,
    GpComputeEvent *const *dependencies, int32_t dependency_count,
    char *error, size_t error_size);
GpComputeEvent *gp_compute_enqueue_axpy(
    GpComputeQueue *queue, GpComputeView *y, double alpha,
    const GpComputeView *x,
    GpComputeEvent *const *dependencies, int32_t dependency_count,
    char *error, size_t error_size);
GpComputeEvent *gp_compute_enqueue_dot(
    GpComputeQueue *queue, const GpComputeView *x, const GpComputeView *y,
    GpComputeView **result,
    GpComputeEvent *const *dependencies, int32_t dependency_count,
    char *error, size_t error_size);
GpComputeEvent *gp_compute_enqueue_mm(
    GpComputeQueue *queue, const GpComputeView *a, const GpComputeView *b,
    GpComputeView **result,
    GpComputeEvent *const *dependencies, int32_t dependency_count,
    char *error, size_t error_size);

GpComputeKernel *gp_compute_kernel_new(
    GpComputeEngine *engine, const char *name,
    const char *source, size_t source_length,
    char *error, size_t error_size);
void gp_compute_kernel_free(GpComputeKernel *kernel);
GpComputeEngine *gp_compute_kernel_engine(const GpComputeKernel *kernel);
GpComputeEvent *gp_compute_enqueue_kernel(
    GpComputeQueue *queue, GpComputeKernel *kernel,
    const uint64_t *global_sizes, int32_t work_dimension,
    const GpComputeKernelArgument *arguments, int32_t argument_count,
    GpComputeEvent *const *dependencies, int32_t dependency_count,
    char *error, size_t error_size);

#ifdef __cplusplus
}
#endif

#endif
