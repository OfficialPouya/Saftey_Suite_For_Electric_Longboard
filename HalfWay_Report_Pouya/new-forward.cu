#include <cmath>
#include <iostream>
#include "gpu-new-forward.h"
#define TILE_WIDTH 16 // We will use 4 for small examples.
__global__ void conv_forward_kernel(float *y, const float *x, const float *k, const int B, const int M, const int C, const int H, const int W, const int K)
{
    /*
    Modify this function to implement the forward pass described in Chapter 16.
    We have added an additional dimension to the tensors to support an entire mini-batch
    The goal here is to be correct AND fast.

    Function paramter definitions:
    y - output
    x - input
    k - kernel
    B - batch_size (number of images in x)
    M - number of output feature maps
    C - number of input feature maps
    H - input height dimension
    W - input width dimension
    K - kernel height and width (K x K)
    */

    const int H_out = H - K + 1;
    const int W_out = W - K + 1;
    // (void)H_out; // silence declared but never referenced warning. remove this line when you start working
    // (void)W_out; // silence declared but never referenced warning. remove this line when you start working

    // We have some nice #defs for you below to simplify indexing. Feel free to use them, or create your own.
    // An example use of these macros:
    // float a = y4d(0,0,0,0)
    // y4d(0,0,0,0) = a

#define y4d(i3, i2, i1, i0) y[(i3) * (M * H_out * W_out) + (i2) * (H_out * W_out) + (i1) * (W_out) + i0]
#define x4d(i3, i2, i1, i0) x[(i3) * (C * H * W) + (i2) * (H * W) + (i1) * (W) + i0]
#define k4d(i3, i2, i1, i0) k[(i3) * (C * K * K) + (i2) * (K * K) + (i1) * (K) + i0]

    // Insert your GPU convolution kernel code here
   /*
    int m = blockIdx.x;
    int h = (blockIdx.y / W_grid) * TILE_WIDTH + threadIdx.y;
    int w = (blockIdx.y % W_grid) * TILE_WIDTH + threadIdx.x;
    float acc = 0.0f;
    for (int c = 0; c < C; c++) { // sum over all input channels
    for (int p = 0; p < K; p++) // loop over KxK filter
    for (int q = 0; q < K; q++)
    acc += X[c, h + p, w + q] * W[m, c, p, q];
    }
    Y[m, h, w] = acc;
   */

    int W_grid = ceil(W_out/(1.0 * TILE_WIDTH)); // number of horizontal tiles per output map
    int H_grid = ceil(H_out/(1.0 * TILE_WIDTH)); // number of vertical tiles per output map

    int n = blockIdx.x;
    int m = blockIdx.y;
    int h = (blockIdx.z / W_grid) * TILE_WIDTH + threadIdx.y;
    int w = (blockIdx.z % W_grid) * TILE_WIDTH + threadIdx.x;
    float acc = 0.0f;
    __syncthreads();  // did increase accuracy
    if(h < H_out && w < W_out){  // increases accuracy , checking if in bound
        for (int c = 0; c < C; c++) { // sum over all input channels
            for (int p = 0; p < K; p++){
                for (int q = 0; q < K; q++){
                    acc += x4d(n, c, h + p, w + q) * k4d(m, c, p, q);
                }
            }
        }
        y4d(n, m, h, w) = acc;
    }
    __syncthreads();  // did increase accuracy
#undef y4d
#undef x4d
#undef k4d
}

	
__host__ void GPUInterface::conv_forward_gpu_prolog(const float *host_y, const float *host_x, const float *host_k, float **device_y_ptr, float **device_x_ptr, float **device_k_ptr, const int B, const int M, const int C, const int H, const int W, const int K)
{
    // Allocate memory and copy over the relevant data structures to the GPU
    float *device_y;
    float *device_x;
    float *device_k;
    
    const int H_out = H - K + 1;
    const int W_out = W - K + 1;

    int size_x = B * C * H * W * sizeof(float);
    int size_y = B * M * H_out * W_out * sizeof(float);
    int size_k = M * C * K * K * sizeof(float);

    cudaMalloc((void **) &device_k, size_k);
    cudaMalloc((void **) &device_x, size_x);
    cudaMalloc((void **) &device_y, size_y);

    cudaMemcpy(device_x, host_x, size_x, cudaMemcpyHostToDevice);
    cudaMemcpy(device_k, host_k, size_k, cudaMemcpyHostToDevice);
    // We pass double pointers for you to initialize the relevant device pointers,
    //  which are passed to the other two functions.

    // Useful snippet for error checking
    // cudaError_t error = cudaGetLastError();
    // if(error != cudaSuccess)
    // {
    //     std::cout<<"CUDA error: "<<cudaGetErrorString(error)<<std::endl;
    //     exit(-1);
    // }

    *device_x_ptr = device_x;
    *device_y_ptr = device_y;
    *device_k_ptr = device_k;

}


__host__ void GPUInterface::conv_forward_gpu(float *device_y, const float *device_x, const float *device_k, const int B, const int M, const int C, const int H, const int W, const int K)
{
    // Set the kernel dimensions and call the kernel
    
    const int H_out = H - K + 1;
    const int W_out = W - K + 1;
    
    int W_grid = ceil(W_out/(1.0 * TILE_WIDTH)); // number of horizontal tiles per output map
    int H_grid = ceil(H_out/(1.0 * TILE_WIDTH)); // number of vertical tiles per output map
    int Y = H_grid * W_grid;
    dim3 blockDim(TILE_WIDTH, TILE_WIDTH, 1); // output tile for untiled code
    dim3 gridDim(B, M, Y);
    conv_forward_kernel <<< gridDim, blockDim >>>(device_y, device_x, device_k, B, M, C, H, W, K);

}


__host__ void GPUInterface::conv_forward_gpu_epilog(float *host_y, float *device_y, float *device_x, float *device_k, const int B, const int M, const int C, const int H, const int W, const int K)
{
    const int H_out = H - K + 1;
    const int W_out = W - K + 1;
    int size_y = B * M * H_out * W_out * sizeof(float);
    // Copy the output back to host
    cudaMemcpy(host_y, device_y, size_y, cudaMemcpyDeviceToHost);
    // Free device memory
    cudaFree(device_x);
    cudaFree(device_y);
    cudaFree(device_k);
}


__host__ void GPUInterface::get_device_properties()
{
    int deviceCount;
    cudaGetDeviceCount(&deviceCount);

    for(int dev = 0; dev < deviceCount; dev++)
    {
        cudaDeviceProp deviceProp;
        cudaGetDeviceProperties(&deviceProp, dev);

        std::cout<<"Device "<<dev<<" name: "<<deviceProp.name<<std::endl;
        std::cout<<"Computational capabilities: "<<deviceProp.major<<"."<<deviceProp.minor<<std::endl;
        std::cout<<"Max Global memory size: "<<deviceProp.totalGlobalMem<<std::endl;
        std::cout<<"Max Constant memory size: "<<deviceProp.totalConstMem<<std::endl;
        std::cout<<"Max Shared memory size per block: "<<deviceProp.sharedMemPerBlock<<std::endl;
        std::cout<<"Max threads per block: "<<deviceProp.maxThreadsPerBlock<<std::endl;
        std::cout<<"Max block dimensions: "<<deviceProp.maxThreadsDim[0]<<" x, "<<deviceProp.maxThreadsDim[1]<<" y, "<<deviceProp.maxThreadsDim[2]<<" z"<<std::endl;
        std::cout<<"Max grid dimensions: "<<deviceProp.maxGridSize[0]<<" x, "<<deviceProp.maxGridSize[1]<<" y, "<<deviceProp.maxGridSize[2]<<" z"<<std::endl;
        std::cout<<"Warp Size: "<<deviceProp.warpSize<<std::endl;
    }
}

