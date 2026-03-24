#ifndef _VGA_BALL_H
#define _VGA_BALL_H

#ifdef __KERNEL__
#include <linux/ioctl.h>
#else
#include <sys/ioctl.h>
#endif

typedef struct {
  unsigned int x;
  unsigned int y;
} vga_ball_arg_t;

#define VGA_BALL_MAGIC 'q'

/* ioctls and their arguments */
#define VGA_BALL_WRITE_POSITION _IOW(VGA_BALL_MAGIC, 1, vga_ball_arg_t)
#define VGA_BALL_READ_POSITION  _IOR(VGA_BALL_MAGIC, 2, vga_ball_arg_t)

#endif
