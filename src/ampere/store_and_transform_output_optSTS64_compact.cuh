// Copyright 2021 Roberto Lopez Castro
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#include "../config.hpp"

#ifndef _OUTPUT_KERNEL_OPT1_
#define _OUTPUT_KERNEL_OPT1_
extern "C"
{
    
__device__ void  transform_output_tile(float2 *pOutputs, float2 *C_tile, float2 *At,
                                      int tiles_dim, int round, int in_n, int c_tensor, int c_glb_offset,
                                      short mask, int out_w){             
  c_tensor += (((round)/2)*32 + ((round)%2)*2)*c_glb_offset/2;  
  int x, x1;

  
  #pragma unroll
  for(int j=0; j<4; j++){
      At[j].x = C_tile[j].x + C_tile[4+j].x + C_tile[8+j].x;
      At[j].y = C_tile[j].y + C_tile[4+j].y + C_tile[8+j].y;
      At[4+j].x = C_tile[4+j].x - C_tile[8+j].x - C_tile[12+j].x;
      At[4+j].y = C_tile[4+j].y - C_tile[8+j].y - C_tile[12+j].y;
  }
  
  x = in_n/2;
  pOutputs[c_tensor].x = At[0].x + At[1].x + At[2].x;
  pOutputs[c_tensor].y = At[0].y + At[1].y + At[2].y;

  if(mask&0x2){
    pOutputs[x + c_tensor].x = At[1].x - At[2].x - At[3].x;
    pOutputs[x + c_tensor].y = At[1].y - At[2].y - At[3].y;
  }

  //x1 = in_n*(tiles_dim-1) + x;
  x1 = in_n*(tiles_dim-(out_w%2)) + (out_w%2)*x;
  if(mask&0x4){
    pOutputs[x1 + c_tensor].x = At[4].x + At[5].x + At[6].x;
    pOutputs[x1 + c_tensor].y = At[4].y + At[5].y + At[6].y;
  }   
  
  if(mask&0x8){
    pOutputs[x1 + x + c_tensor].x = At[5].x - At[6].x - At[7].x;
    pOutputs[x1 + x + c_tensor].y = At[5].y - At[6].y - At[7].y;
  }
}

__device__ __forceinline__ void store_output_tile(float4 acumm_smem[][16], float *shared_mem, float *C, int out_h, int out_w, int tiles_dim, int in_n, float4 *input_frag_mem, float4* filter_frag_mem,  short mask){
  
  float2 *output_smem = (float2 *) shared_mem;
  float2 *accumulator = (float2 *) acumm_smem;
  float2 *C_out = (float2*)C;

  float2 *C_tile = (float2*) input_frag_mem;
  float2 *At = (float2*) filter_frag_mem;

  mask = 0x000F;
  if((blockIdx.y/tiles_dim)==(tiles_dim-1) && out_w%2) mask&=0x0003;
  if(!((blockIdx.y+1)%tiles_dim) && out_w%2)           mask&=0X0005;
  
  // output transpose step
  int t,j;
  int acumm1, acumm2;
  // For transposing
  t = threadIdx.x%8/2;
  acumm1 = t*18 + threadIdx.x%2 + (threadIdx.x/16)*2 + ((threadIdx.x/8)%2)*8;
  acumm2 = acumm1+4;
  acumm1 = acumm1 - acumm1/((t+1)*16)*16 + t*16;  
  acumm2 = acumm2 - acumm2/((t+1)*16)*16 + t*16;
  t=0;
                       
  int acumm4 = BN_p*16 ; //*4
  int idx  = threadIdx.y * BN_p;
  int idx2 = idx + BN_p*8; //(BN_p*2 *8)/2

  // For transformating
  int offset = BN_p *2; //*2/2
  
  int init = (threadIdx.y%4)*(16+2)*2 + threadIdx.x;
  init = init - init/((threadIdx.y%4+1)*32)*32 + threadIdx.y%4*32;
  init += (threadIdx.y/4)*BN_p*16*2;

  int c_glb_offset = in_n*out_h*out_w;
  int c_tensor = blockIdx.z*c_glb_offset*BK + (blockIdx.y%tiles_dim)*in_n*2 + (blockIdx.y/tiles_dim)*in_n*out_w*2 + blockIdx.x*BN + (threadIdx.x%16)*2+
                ((threadIdx.x/16)*16 + (threadIdx.y%4)*4 + threadIdx.y/4)*c_glb_offset;
  c_tensor/=2; 

  // k=0, block 0
  *( (float2*) (output_smem + idx + acumm1) )  = *(accumulator);
  *( (float2*) (output_smem + idx + acumm1 + 16) )  = *(accumulator+1);
  *( (float2*) (output_smem + idx + acumm2) )  = *(accumulator+2);
  *( (float2*) (output_smem + idx + acumm2 + 16) )  = *(accumulator+3);
  
  // K=1, block 0
  *( (float2*) (output_smem + idx + acumm4 + acumm1) )  = *(accumulator+4); 
  *( (float2*) (output_smem + idx + acumm4 + acumm1 + 16) )  = *(accumulator+5);
  *( (float2*) (output_smem + idx + acumm4 + acumm2) )  = *(accumulator+6);
  *( (float2*) (output_smem + idx + acumm4 + acumm2 + 16) )  = *(accumulator+7);
  
  // k=0, block 1
  *( (float2*) (output_smem + idx2 + acumm1) ) = *(accumulator+32);
  *( (float2*) (output_smem + idx2 + acumm1 + 16) ) = *(accumulator+33); 
  *( (float2*) (output_smem + idx2 + acumm2) ) = *(accumulator+34);
  *( (float2*) (output_smem + idx2 + acumm2 + 16) ) = *(accumulator+35); 
  
  // K=1, block 1
  *( (float2*) (output_smem + idx2 + acumm4 + acumm1) ) = *(accumulator+36);
  *( (float2*) (output_smem + idx2 + acumm4 + acumm1 + 16) ) = *(accumulator+37);
  *( (float2*) (output_smem + idx2 + acumm4 + acumm2) ) = *(accumulator+38);
  *( (float2*) (output_smem + idx2 + acumm4 + acumm2 + 16) ) = *(accumulator+39);
  
  j=0; t+=8;

  #pragma unroll                                  
  for(int round=0; round<3; round++){
    
    __syncthreads();

    int disp = j/2*(BN_p*2*16)*2;
    #pragma unroll
    for(int i=0; i<16; i++){
      C_tile[i].x = shared_mem[disp + i*offset + init];
      C_tile[i].y = shared_mem[disp + i*offset + init + 32];
    }

    // transform output tiles
    transform_output_tile(C_out, C_tile, At, tiles_dim, (round/2)*2+j/2, in_n, c_tensor, c_glb_offset, mask, out_w);

    j = 2 - j; //switch between 0 and 2
      
    // k=0, block 0
    *( (float2*) (output_smem + idx + (j)*acumm4 + acumm1) )  = *(accumulator+t);
    *( (float2*) (output_smem + idx + (j)*acumm4 + acumm1 + 16) )  = *(accumulator+t+1);
    *( (float2*) (output_smem + idx + (j)*acumm4 + acumm2) )  = *(accumulator+t+2);
    *( (float2*) (output_smem + idx + (j)*acumm4 + acumm2 + 16) )  = *(accumulator+t+3);
    
    // K=1, block 0
    *( (float2*) (output_smem + idx + (j+1)*acumm4 + acumm1) )  = *(accumulator+t+4); 
    *( (float2*) (output_smem + idx + (j+1)*acumm4 + acumm1 + 16) )  = *(accumulator+t+5);
    *( (float2*) (output_smem + idx + (j+1)*acumm4 + acumm2) )  = *(accumulator+t+6);
    *( (float2*) (output_smem + idx + (j+1)*acumm4 + acumm2 + 16) )  = *(accumulator+t+7);
    
    // k=0, block 1
    *( (float2*) (output_smem + idx2 + (j)*acumm4 + acumm1) ) = *(accumulator+t+32);
    *( (float2*) (output_smem + idx2 + (j)*acumm4 + acumm1 + 16) ) = *(accumulator+t+33); 
    *( (float2*) (output_smem + idx2 + (j)*acumm4 + acumm2) ) = *(accumulator+t+34);
    *( (float2*) (output_smem + idx2 + (j)*acumm4 + acumm2 + 16) ) = *(accumulator+t+35); 
    
    // K=1, block 1
    *( (float2*) (output_smem + idx2 + (j+1)*acumm4 + acumm1) ) = *(accumulator+t+36);
    *( (float2*) (output_smem + idx2 + (j+1)*acumm4 + acumm1 + 16) ) = *(accumulator+t+37);
    *( (float2*) (output_smem + idx2 + (j+1)*acumm4 + acumm2) ) = *(accumulator+t+38);
    *( (float2*) (output_smem + idx2 + (j+1)*acumm4 + acumm2 + 16) ) = *(accumulator+t+39);
      
    t+=8;

  }

  __syncthreads();

  int disp = j/2*(BN_p*2*16)*2;
  #pragma unroll
  for(int i=0; i<16; i++){
    C_tile[i].x = shared_mem[disp + i*offset + init];
    C_tile[i].y = shared_mem[disp + i*offset + init + 32];
  }
  // transform output tiles
  transform_output_tile(C_out, C_tile, At, tiles_dim, 2+j/2, in_n, c_tensor, c_glb_offset, mask, out_w);
}

}
#endif     
