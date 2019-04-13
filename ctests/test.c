#include <mpi.h>

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>  /* getopt */
#include <string.h>  /* memset */

#include "../gptl.h"

#ifdef THREADED_OMP
#include <omp.h>
#endif

static int iam = 0;
static int nproc = 1;    /* number of MPI tasks (default 1) */
static int nthreads = 1; /* number of threads (default 1) */

double sub (int);

int main (int argc, char **argv)
{

  int iter;
  int counter;
  int c;
  int tnum = 0;
  int resultlen;
  int ret;
  double value;
  extern char *optarg;

  if (MPI_Init (&argc, &argv) != MPI_SUCCESS) {
    printf ("Failure from MPI_Init\n");
    return 1;
  }

  /*
  ** If ENABLE_PMPI is set, GPTL was initialized in MPI_Init
  */

  ret = GPTLinitialize ();
  int i = 0 ;
  for (i = 0 ; i < 1000 ; i ++) {
    ret = GPTLstart ("total");	 
    ret = GPTLstop ("total");
  }
  ret = GPTLpr (iam);


  if (GPTLpr_summary (MPI_COMM_WORLD) != 0)
    return 1;

  if (GPTLpr_summary_file (MPI_COMM_WORLD, "timing.summary.duplicate") != 0)
    return 1;

  ret = MPI_Finalize ();

  if (GPTLfinalize () != 0)
    return 1;

  return 0;
}

double sub (int iter)
{
  unsigned long usec;
  unsigned long looplen = iam*iter*100000;
  unsigned long i;
  double sum;
  int ret;

  ret = GPTLstart ("sub");
  /* Sleep msec is mpi rank + thread number */
  usec = 1000 * (iam * iter);

  ret = GPTLstart ("sleep");
  usleep (usec);
  ret = GPTLstop ("sleep");

  ret = GPTLstart ("work");
  sum = 0.;
  ret = GPTLstart ("add");
  for (i = 0; i < looplen; ++i) {
    sum += i;
  }
  ret = GPTLstop ("add");

  ret = GPTLstart ("madd");
  for (i = 0; i < looplen; ++i) {
    sum += i*1.1;
  }
  ret = GPTLstop ("madd");

  ret = GPTLstart ("div");
  for (i = 0; i < looplen; ++i) {
    sum /= 1.1;
  }
  ret = GPTLstop ("div");
  ret = GPTLstop ("work");
  ret = GPTLstop ("sub");
  return sum;
}
