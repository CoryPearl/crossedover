/* Checks x87 square root and the PC24/PC53 precision boundary; timing is diagnostic only. */
#include <windows.h>
#include <stdio.h>
#include <math.h>
static double add_x87(double a,double b) {double out;__asm__ volatile("fldl %1; faddl %2; fstpl %0":"=m"(out):"m"(a),"m"(b):"st");return out;}
int main(void) {
 LARGE_INTEGER f,a,b;double in=4,out=0;QueryPerformanceFrequency(&f);QueryPerformanceCounter(&a);
 for(int i=0;i<100000;i++)__asm__ volatile("fldl %1; fsqrt; fstpl %0":"=m"(out):"m"(in):"st");
 QueryPerformanceCounter(&b);printf("sqrt_iterations=100000 ms=%.3f result=%.17g\n",1000.0*(b.QuadPart-a.QuadPart)/f.QuadPart,out);fflush(stdout);
 unsigned short original,pc24,pc53;__asm__ volatile("fnstcw %0":"=m"(original));pc24=original&~0x300;pc53=(original&~0x300)|0x200;
 __asm__ volatile("fldcw %0"::"m"(pc24));double r24=add_x87(1.0,0x1p-24);
 __asm__ volatile("fldcw %0"::"m"(pc53));double r53=add_x87(1.0,0x1p-24);
 __asm__ volatile("fldcw %0"::"m"(original));printf("pc24=%.17g pc53=%.17g precision_valid=%d\n",r24,r53,r24==1.0 && r53==1.0+0x1p-24);
 return out==2.0 && r24==1.0 && r53==1.0+0x1p-24?0:1;
}
