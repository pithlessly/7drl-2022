#include <termios.h>
#include <stdio.h>

const int STDOUT_FILENO = 1;
static struct termios old_settings;

// TODO: error handling

void enter_raw_mode() {
    struct termios settings;
    tcgetattr(STDOUT_FILENO, &settings);
    old_settings = settings;
    cfmakeraw(&settings);
    tcsetattr(STDOUT_FILENO, TCSANOW, &settings);
}

void exit_raw_mode() {
    tcsetattr(STDOUT_FILENO, TCSANOW, &old_settings);
}
