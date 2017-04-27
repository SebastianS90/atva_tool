#define NUM 9
int x = 0;
int y = 0;
#include <pthread.h>
#include <assert.h>

void * t1()
{
  for (int i =1; i<NUM; i++) {
    y = y+x;
    x = x+y ;
  }
 
  pthread_exit(NULL);
}

void * t2()
{
  
  for (int i =1; i<NUM; i++) {
    y = y - x;
    x = x - y;
  }

  for (int i =1; i<NUM; i++) {
    y = y * 2;
    x = x /3;
    if (y >= NUM) {
      y = 1;
    }
    if (x == 0) {
      x = NUM;
    }
  }

  for (int i =1; i<NUM; i++) {
    y = y / 3;
    if (y == 0) {
      y = NUM;
    }
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
  
  assert(y != 0 && x != 0);
  return 0;
}

