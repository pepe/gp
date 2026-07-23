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

enum GpComputeDType {
    GP_COMPUTE_F32 = 1,
    GP_COMPUTE_F64 = 2,
    GP_COMPUTE_I32 = 3,
};

GpComputeEngine *gp_compute_cpp_engine(void);
const char *gp_compute_engine_name(const GpComputeEngine *engine);

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

#ifdef __cplusplus
}
#endif

#endif
