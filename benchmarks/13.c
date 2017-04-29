#define NUM 9
int x = 0;
int y = 0;
#include <pthread.h>
#include <assert.h>

void * t1()
{
  for (int i =0; i<NUM; i++) {
    y = y+1;
  }
  x = 1;
      
  pthread_exit(NULL);
}

void * t2()
{
  for (int i =0; i<NUM; i++) {
    y = y+2;
  }
  while (x == 0) { }

  x = y;
  
  for (int i =0; i<NUM; i++) {
    y = y + 1 ;
  }

  for (int i =0; i<NUM; i++) {
    y = y + 2;
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
  
  assert(y == x + 3*NUM);
  //  assert(y >=0);
  return 0;
}

