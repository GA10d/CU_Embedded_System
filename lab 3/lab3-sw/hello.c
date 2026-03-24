/*
 * Userspace program that communicates with the vga_ball device driver
 * through ioctls
 *
 * Stephen A. Edwards
 * Columbia University
 */

#include <stdio.h>
#include "vga_ball.h"
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

int vga_ball_fd;

/* Read and print the ball position */
void print_ball_position(void)
{
  vga_ball_arg_t vla;
  
  if (ioctl(vga_ball_fd, VGA_BALL_READ_POSITION, &vla)) {
      perror("ioctl(VGA_BALL_READ_POSITION) failed");
      return;
  }
  printf("(%u, %u)\n", vla.x, vla.y);
}

/* Set the ball position */
void set_ball_position(unsigned int x, unsigned int y)
{
  vga_ball_arg_t vla;
  vla.x = x;
  vla.y = y;
  if (ioctl(vga_ball_fd, VGA_BALL_WRITE_POSITION, &vla)) {
      perror("ioctl(VGA_BALL_WRITE_POSITION) failed");
      return;
  }
}

int main()
{
  int i, dx = 3, dy = 2;
  static const char filename[] = "/dev/vga_ball";
  unsigned int x = 320, y = 240;
  const unsigned int radius = 8;
  const unsigned int max_x = 639 - radius;
  const unsigned int max_y = 479 - radius;
  const unsigned int min_x = radius;
  const unsigned int min_y = radius;

  printf("VGA ball Userspace program started\n");

  if ( (vga_ball_fd = open(filename, O_RDWR)) == -1) {
    fprintf(stderr, "could not open %s\n", filename);
    return -1;
  }

  printf("initial state: ");
  print_ball_position();

  for (i = 0 ; i < 600 ; i++) {
    if (x <= min_x || x >= max_x)
      dx = -dx;
    if (y <= min_y || y >= max_y)
      dy = -dy;

    x += dx;
    y += dy;

    set_ball_position(x, y);
    if ((i % 30) == 0)
      print_ball_position();
    usleep(16000);
  }
  
  printf("VGA BALL Userspace program terminating\n");
  return 0;
}
