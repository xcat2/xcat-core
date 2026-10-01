project(
  'xcat-genesis-console',
  'c',
  version: '0.1',
  default_options: [
    'c_std=c17',
    'warning_level=3',
    'werror=true',
  ],
)

add_project_arguments('-D_POSIX_C_SOURCE=200809L', language: 'c')

console_sources = files(
  'src/main.c',
  'src/newt_ui.c',
  'src/plain_ui.c',
  'src/shell.c',
  'src/state.c',
  'src/support.c',
)

executable(
  'xcat-genesis-console',
  console_sources,
  dependencies: [dependency('libnewt'), dependency('libsystemd')],
  install: true,
  install_dir: get_option('sbindir'),
)
