#define NUM 15
#define SUM (3*NUM)
int x = 0;
int y = 0;
int z = 0;

#include <pthread.h>
#include <assert.h>
//#include <stdio.h>
#include <stdlib.h>

//pthread_mutex_t *data1Lock;

void * t1()
{
  for (int i =0; i<NUM; i++) {
    y = y+1;
    z = z + y;
  }
  x = 1;
      
  pthread_exit(NULL);
}

void * t2()
{
  for (int i =0; i<NUM; i++) {
    y = y+2;
    z = z + y;
    if (z > NUM) {
      z = 0;
    }
    //    z = z + 2*y;
  }
  
  while (z < NUM && x != 1) { }
  
  for (int i =0; i<NUM; i++) {
    y = y * 2;
    /* z = z - y; */
    /* if (z < 0) { */
    /*   z = y; */
    /* } */
  }

}

int main()
{
  pthread_t id1, id2;
  //  data1Lock = (pthread_mutex_t *) malloc(sizeof(pthread_mutex_t));

  pthread_create(&id1, NULL, t1, NULL);
  pthread_create(&id2, NULL, t2, NULL);

  pthread_join(id1, (void *)0);
  pthread_join(id2, (void *)0);

  //printf("%d\n",y);
  
  assert(z <= NUM);
  return 0;
}
