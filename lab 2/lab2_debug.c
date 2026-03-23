/*
 *
 * CSEE 4840 Lab 2
 *
 * Name/UNI: Please Change to Yourname (pcy2301)
 *
 * Framebuffer UI (chat window + 2-line input), basic editing,
 * thread-safe rendering, plus:
 *   - Shift-chord stabilization (pending key commit)
 *   - Software key repeat (hold-to-repeat)
 */

#include "fbputchar.h"
#include "usbkeyboard.h"

#include <arpa/inet.h>
#include <errno.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

/* Update SERVER_HOST to be the IP address of the chat server you are connecting to */
/* arthur.cs.columbia.edu */
#define SERVER_HOST "128.59.19.114"
#define SERVER_PORT 42000

#define BUFFER_SIZE 128

/*
 * NOTE: The provided framebuffer text grid in the skeleton is typically 64 cols x 24 rows.
 * Your original code drew 64 chars on rows 0 and 23, so we keep that geometry here.
 */
#define FB_COLS 64
#define FB_ROWS 24

#define INPUT_ROWS 2
#define SEP_ROWS   1

#define SEP_ROW        (FB_ROWS - INPUT_ROWS - SEP_ROWS)   /* 21 */
#define INPUT_ROW0     (SEP_ROW + 1)                       /* 22 */
#define INPUT_ROW1     (SEP_ROW + 2)                       /* 23 */

/* Keep a title line at row 0; chat messages start from row 1 */
#define TITLE_ROW      0
#define CHAT_TOP       1
#define CHAT_VISIBLE   (SEP_ROW - CHAT_TOP)                 /* rows 1..20 (20 rows) */

#define CHAT_HISTORY   200
#define INPUT_CAP      (FB_COLS * INPUT_ROWS)               /* 128 chars */

/* ---- Timing knobs ---- */
#define PENDING_TIMEOUT_MS  25   /* wait a tiny bit for Shift to show up */
#define REPEAT_DELAY_MS     350  /* start repeating after 350ms */
#define REPEAT_RATE_MS      55   /* repeat every 55ms */

/* Socket file descriptor */
static int sockfd = -1;

static struct libusb_device_handle *keyboard = NULL;
static uint8_t endpoint_address;

static pthread_t network_thread;
static void *network_thread_f(void *);

static volatile int running = 1;

/* ---------- UI state ---------- */

typedef struct {
  /* chat ring buffer (already wrapped into FB_COLS lines) */
  char chat[CHAT_HISTORY][FB_COLS + 1];
  int chat_head;   /* next write index */
  int chat_count;  /* number of valid lines (<= CHAT_HISTORY) */

  /* input buffer (2 lines max) */
  char input[INPUT_CAP + 1];
  int cursor; /* 0..strlen(input) */
} UIState;

static UIState ui;
static pthread_mutex_t ui_mutex = PTHREAD_MUTEX_INITIALIZER;

/* ---------- Small time helpers ---------- */
static long elapsed_ms(const struct timespec *start, const struct timespec *end) {
  long sec = (long)(end->tv_sec - start->tv_sec);
  long nsec = (long)(end->tv_nsec - start->tv_nsec);
  return sec * 1000 + nsec / 1000000;
}

static void now_ts(struct timespec *t) {
  clock_gettime(CLOCK_MONOTONIC, t);
}

/* ---------- Framebuffer helpers ---------- */

static void fb_clear_row(int row) {
  for (int c = 0; c < FB_COLS; c++) fbputchar(' ', row, c);
}

static void fb_clear_screen(void) {
  for (int r = 0; r < FB_ROWS; r++) fb_clear_row(r);
}

static void ui_draw_separator_locked(void) {
  for (int c = 0; c < FB_COLS; c++) fbputchar('-', SEP_ROW, c);
}

static void ui_redraw_chat_locked(void) {
  /* clear chat area */
  for (int r = 0; r < CHAT_VISIBLE; r++) fb_clear_row(CHAT_TOP + r);

  /* show the most recent CHAT_VISIBLE lines */
  int to_show = ui.chat_count;
  if (to_show > CHAT_VISIBLE) to_show = CHAT_VISIBLE;

  /* oldest line index among those we show */
  int start = ui.chat_head - to_show;
  while (start < 0) start += CHAT_HISTORY;

  for (int i = 0; i < to_show; i++) {
    int idx = (start + i) % CHAT_HISTORY;
    fbputs(ui.chat[idx], CHAT_TOP + i, 0);
  }
}

static void ui_redraw_input_locked(void) {
  fb_clear_row(INPUT_ROW0);
  fb_clear_row(INPUT_ROW1);

  /* draw input text across 2 lines */
  int len = (int)strlen(ui.input);
  for (int i = 0; i < len && i < INPUT_CAP; i++) {
    int row = INPUT_ROW0 + (i / FB_COLS);
    int col = i % FB_COLS;
    if (row > INPUT_ROW1) break;
    fbputchar(ui.input[i], row, col);
  }

  /* draw cursor as '_' at cursor position */
  int cur = ui.cursor;
  if (cur < 0) cur = 0;
  if (cur > len) cur = len;
  if (cur > INPUT_CAP) cur = INPUT_CAP;

  int crow = INPUT_ROW0 + (cur / FB_COLS);
  int ccol = cur % FB_COLS;
  if (crow <= INPUT_ROW1) {
    fbputchar('_', crow, ccol);
  }
}

static void chat_push_line_locked(const char *line) {
  strncpy(ui.chat[ui.chat_head], line, FB_COLS);
  ui.chat[ui.chat_head][FB_COLS] = '\0';

  ui.chat_head = (ui.chat_head + 1) % CHAT_HISTORY;
  if (ui.chat_count < CHAT_HISTORY) ui.chat_count++;
}

/* Wrap msg into FB_COLS lines, split on '\n', push into chat ring */
static void ui_add_message_locked(const char *msg) {
  char line[FB_COLS + 1];
  int lc = 0;

  for (const char *p = msg; *p; p++) {
    char ch = *p;

    if (ch == '\r') continue; /* ignore CR */

    if (ch == '\n') {
      line[lc] = '\0';
      chat_push_line_locked(line);
      lc = 0;
      continue;
    }

    line[lc++] = ch;
    if (lc >= FB_COLS) {
      line[FB_COLS] = '\0';
      chat_push_line_locked(line);
      lc = 0;
    }
  }

  if (lc > 0) {
    line[lc] = '\0';
    chat_push_line_locked(line);
  }

  ui_redraw_chat_locked();
  ui_draw_separator_locked();
}

static void ui_init(void) {
  pthread_mutex_lock(&ui_mutex);

  memset(&ui, 0, sizeof(ui));
  fb_clear_screen();

  fbputs("CSEE 4840 Chat", TITLE_ROW, 0);

  ui_draw_separator_locked();
  ui_redraw_input_locked();

  pthread_mutex_unlock(&ui_mutex);
}

/* ---------- Input editing ---------- */

static void input_insert_char_locked(char ch) {
  if (ch == '\0') return;

  int len = (int)strlen(ui.input);
  if (len >= INPUT_CAP) return;

  if (ui.cursor < 0) ui.cursor = 0;
  if (ui.cursor > len) ui.cursor = len;

  memmove(&ui.input[ui.cursor + 1], &ui.input[ui.cursor], (size_t)(len - ui.cursor + 1));
  ui.input[ui.cursor] = ch;
  ui.cursor++;
}

static void input_backspace_locked(void) {
  int len = (int)strlen(ui.input);
  if (ui.cursor <= 0 || len <= 0) return;

  if (ui.cursor > len) ui.cursor = len;

  memmove(&ui.input[ui.cursor - 1], &ui.input[ui.cursor], (size_t)(len - ui.cursor + 1));
  ui.cursor--;
}

static void input_move_left_locked(void) {
  if (ui.cursor > 0) ui.cursor--;
}

static void input_move_right_locked(void) {
  int len = (int)strlen(ui.input);
  if (ui.cursor < len) ui.cursor++;
}

static void input_clear_locked(void) {
  ui.input[0] = '\0';
  ui.cursor = 0;
}

/* ---------- HID keycode -> ASCII ---------- */

static int shift_down(uint8_t modifiers) {
  /* Left shift (0x02) or Right shift (0x20) */
  return (modifiers & 0x22) != 0;
}

static char hid_to_ascii(uint8_t keycode, uint8_t modifiers) {
  const int shift = shift_down(modifiers);

  /* Letters a-z */
  if (keycode >= 0x04 && keycode <= 0x1d) {
    char base = (char)('a' + (keycode - 0x04));
    return shift ? (char)(base - 'a' + 'A') : base;
  }

  /* Numbers 1-0 */
  if (keycode >= 0x1e && keycode <= 0x27) {
    static const char normal[]  = {'1','2','3','4','5','6','7','8','9','0'};
    static const char shifted[] = {'!','@','#','$','%','^','&','*','(',')'};
    return shift ? shifted[keycode - 0x1e] : normal[keycode - 0x1e];
  }

  switch (keycode) {
    case 0x2c: return ' ';                 /* Space */
    case 0x2d: return shift ? '_' : '-';   /* - _ */
    case 0x2e: return shift ? '+' : '=';   /* = + */
    case 0x2f: return shift ? '{' : '[';   /* [ { */
    case 0x30: return shift ? '}' : ']';   /* ] } */
    case 0x31: return shift ? '|' : '\\';  /* \ | */
    case 0x33: return shift ? ':' : ';';   /* ; : */
    case 0x34: return shift ? '\"' : '\''; /* ' " */
    case 0x35: return shift ? '~' : '`';   /* ` ~ */
    case 0x36: return shift ? '<' : ',';   /* , < */
    case 0x37: return shift ? '>' : '.';   /* . > */
    case 0x38: return shift ? '?' : '/';   /* / ? */
    default: return '\0';
  }
}

static int key_in_prev(uint8_t code, const uint8_t prev[6]) {
  for (int i = 0; i < 6; i++) if (prev[i] == code) return 1;
  return 0;
}

static int key_in_packet(uint8_t code, const struct usb_keyboard_packet *p) {
  for (int i = 0; i < 6; i++) if (p->keycode[i] == code) return 1;
  return 0;
}

/* ---------- Pending-key + Repeat state ---------- */

typedef struct {
  int active;
  uint8_t key;
  uint8_t mods_at_press;
  struct timespec t0;
} PendingKey;

typedef struct {
  int active;
  uint8_t key;
  struct timespec t_start;
  struct timespec t_last;
} RepeatState;

static PendingKey pending = {0};
static RepeatState repeat_state = {0};

/* Commit pending key (choose modifiers depending on situation) */
static void pending_commit(uint8_t commit_mods) {
  pthread_mutex_lock(&ui_mutex);
  char ch = hid_to_ascii(pending.key, commit_mods);
  if (ch != '\0') {
    input_insert_char_locked(ch);
    ui_redraw_input_locked();
  }
  pthread_mutex_unlock(&ui_mutex);
  pending.active = 0;
}

/* Cancel pending key (used when backspace etc. happens before commit) */
static void pending_cancel(void) {
  pending.active = 0;
}

/* Try to commit pending based on current report: shift showed up, timeout, or release */
static void pending_try_commit(const struct usb_keyboard_packet *p) {
  if (!pending.active) return;

  struct timespec now;
  now_ts(&now);

  int still_held = key_in_packet(pending.key, p);
  int shift_now  = shift_down(p->modifiers);
  long ms        = elapsed_ms(&pending.t0, &now);

  if (still_held && shift_now) {
    /* Shift arrived shortly after key press: commit shifted */
    pending_commit(p->modifiers);
  } else if (!still_held) {
    /* Key released before shift arrived: commit unshifted */
    pending_commit(pending.mods_at_press);
  } else if (ms >= PENDING_TIMEOUT_MS) {
    /* Timeout: commit with original modifiers */
    pending_commit(pending.mods_at_press);
  }
}

/* Software key repeat (hold-to-repeat) */
static void repeat_tick(const struct usb_keyboard_packet *p) {
  if (!repeat_state.active) return;

  /* Don't repeat a key that hasn't even been committed yet */
  if (pending.active && pending.key == repeat_state.key) return;

  if (!key_in_packet(repeat_state.key, p)) {
    repeat_state.active = 0;
    repeat_state.key = 0;
    return;
  }

  struct timespec now;
  now_ts(&now);

  long held_ms = elapsed_ms(&repeat_state.t_start, &now);
  long since_last = elapsed_ms(&repeat_state.t_last, &now);

  if (held_ms >= REPEAT_DELAY_MS && since_last >= REPEAT_RATE_MS) {
    pthread_mutex_lock(&ui_mutex);
    char ch = hid_to_ascii(repeat_state.key, p->modifiers); /* use current mods for shift repeat */
    if (ch != '\0') {
      input_insert_char_locked(ch);
      ui_redraw_input_locked();
    }
    pthread_mutex_unlock(&ui_mutex);

    repeat_state.t_last = now;
  }
}

/* ---------- Networking helpers ---------- */

static void send_line_to_server(const char *line) {
  if (sockfd < 0) return;
  if (!line) return;

  size_t len = strlen(line);
  if (len == 0) return;

  /* Send with trailing newline for server friendliness */
  char out[INPUT_CAP + 2];
  if (len > INPUT_CAP) len = INPUT_CAP;

  memcpy(out, line, len);
  if (out[len - 1] != '\n') {
    out[len++] = '\n';
  }
  out[len] = '\0';

  (void)write(sockfd, out, len);
}

int main(void) {
  int err;
  struct sockaddr_in serv_addr;

  struct usb_keyboard_packet packet;
  int transferred;
  uint8_t prev_keys[6] = {0};

  if ((err = fbopen()) != 0) {
    fprintf(stderr, "Error: Could not open framebuffer: %d\n", err);
    exit(1);
  }

  ui_init();

  /* Open the keyboard */
  if ((keyboard = openkeyboard(&endpoint_address)) == NULL) {
    fprintf(stderr, "Did not find a keyboard\n");
    exit(1);
  }

  /* Create a TCP communications socket */
  if ((sockfd = socket(AF_INET, SOCK_STREAM, 0)) < 0) {
    fprintf(stderr, "Error: Could not create socket\n");
    exit(1);
  }

  /* Get the server address */
  memset(&serv_addr, 0, sizeof(serv_addr));
  serv_addr.sin_family = AF_INET;
  serv_addr.sin_port = htons(SERVER_PORT);
  if (inet_pton(AF_INET, SERVER_HOST, &serv_addr.sin_addr) <= 0) {
    fprintf(stderr, "Error: Could not convert host IP \"%s\"\n", SERVER_HOST);
    exit(1);
  }

  /* Connect the socket to the server */
  if (connect(sockfd, (struct sockaddr *)&serv_addr, sizeof(serv_addr)) < 0) {
    fprintf(stderr, "Error: connect() failed. Is the server running? (%s)\n", strerror(errno));
    exit(1);
  }

  pthread_mutex_lock(&ui_mutex);
  ui_add_message_locked("[connected]");
  pthread_mutex_unlock(&ui_mutex);

  /* Start the network thread */
  pthread_create(&network_thread, NULL, network_thread_f, NULL);

  /* Main loop: read keyboard, update input/UI, send on Enter */
  while (running) {
    libusb_interrupt_transfer(keyboard, endpoint_address, (unsigned char *)&packet,
                              sizeof(packet), &transferred, 0);

    if (transferred != (int)sizeof(packet)) continue;

    /* 1) First: pending commit logic (fixes Shift arriving 1 report later) */
    pending_try_commit(&packet);

    /* 2) Then: handle newly pressed keys only (edge detect) */
    for (int i = 0; i < 6; i++) {
      uint8_t code = packet.keycode[i];
      if (code == 0) continue;
      if (key_in_prev(code, prev_keys)) continue;

      /* Special keys */
      if (code == 0x29) { /* ESC */
        pending_cancel();
        running = 0;
        break;
      }

      /* Enter/backspace/arrows should NOT be delayed by pending printable */
      if (code == 0x28) { /* Enter */
        /* Force commit any pending printable before sending */
        if (pending.active) {
          pending_commit(shift_down(packet.modifiers) ? packet.modifiers : pending.mods_at_press);
        }

        pthread_mutex_lock(&ui_mutex);

        char line[INPUT_CAP + 1];
        strncpy(line, ui.input, INPUT_CAP);
        line[INPUT_CAP] = '\0';

        if (strlen(line) > 0) {
          ui_add_message_locked(line); /* echo locally */
        }

        input_clear_locked();
        ui_redraw_input_locked();
        pthread_mutex_unlock(&ui_mutex);

        if (strlen(line) > 0) send_line_to_server(line);
        continue;
      }

      if (code == 0x2a) { /* Backspace */
        /* If a char is pending (not committed yet), just cancel it */
        if (pending.active) {
          pending_cancel();
          continue;
        }
        pthread_mutex_lock(&ui_mutex);
        input_backspace_locked();
        ui_redraw_input_locked();
        pthread_mutex_unlock(&ui_mutex);
        continue;
      }

      if (code == 0x50) { /* Left Arrow */
        if (pending.active) pending_commit(pending.mods_at_press);
        pthread_mutex_lock(&ui_mutex);
        input_move_left_locked();
        ui_redraw_input_locked();
        pthread_mutex_unlock(&ui_mutex);
        continue;
      }

      if (code == 0x4f) { /* Right Arrow */
        if (pending.active) pending_commit(pending.mods_at_press);
        pthread_mutex_lock(&ui_mutex);
        input_move_right_locked();
        ui_redraw_input_locked();
        pthread_mutex_unlock(&ui_mutex);
        continue;
      }

      /* Printable keys */
      char ch_now = hid_to_ascii(code, packet.modifiers);
      if (ch_now == '\0') continue;

      /* Start repeat tracking for this printable key */
      struct timespec now;
      now_ts(&now);
      repeat_state.active = 1;
      repeat_state.key = code;
      repeat_state.t_start = now;
      repeat_state.t_last = now;

      /* If shift is down NOW, commit immediately. Otherwise, delay briefly. */
      if (shift_down(packet.modifiers)) {
        pthread_mutex_lock(&ui_mutex);
        input_insert_char_locked(ch_now);
        ui_redraw_input_locked();
        pthread_mutex_unlock(&ui_mutex);
      } else {
        /* If another pending exists, commit it unshifted first */
        if (pending.active) pending_commit(pending.mods_at_press);

        pending.active = 1;
        pending.key = code;
        pending.mods_at_press = packet.modifiers; /* likely 0 */
        pending.t0 = now;
      }
    }

    /* 3) Repeat tick (hold-to-repeat) */
    repeat_tick(&packet);

    /* 4) Update prev_keys */
    memcpy(prev_keys, packet.keycode, sizeof(prev_keys));
  }

  /* Stop networking */
  pthread_cancel(network_thread);
  shutdown(sockfd, SHUT_RDWR);
  close(sockfd);
  sockfd = -1;

  pthread_join(network_thread, NULL);

  pthread_mutex_lock(&ui_mutex);
  ui_add_message_locked("[disconnected]");
  pthread_mutex_unlock(&ui_mutex);

  return 0;
}

static void *network_thread_f(void *ignored) {
  (void)ignored;

  char recvBuf[BUFFER_SIZE];
  int n;

  while ((n = (int)read(sockfd, recvBuf, BUFFER_SIZE - 1)) > 0) {
    recvBuf[n] = '\0';

    pthread_mutex_lock(&ui_mutex);
    ui_add_message_locked(recvBuf);
    pthread_mutex_unlock(&ui_mutex);
  }

  return NULL;
}
