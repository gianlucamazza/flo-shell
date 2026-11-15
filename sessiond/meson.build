project('flo-sessiond', 'c',
  version: '0.1.0',
  license: 'MIT',
  meson_version: '>=0.60.0',
  default_options: ['c_std=c17', 'warning_level=2', 'werror=true', 'buildtype=debugoptimized'],
)

add_project_arguments('-D_GNU_SOURCE', language: 'c')

cc = meson.get_compiler('c')
add_project_arguments(cc.get_supported_arguments([
  '-Wshadow', '-Wstrict-prototypes', '-Wmissing-prototypes', '-Wformat=2',
  '-Wconversion', '-Wno-sign-conversion', '-fno-common',
]), language: 'c')

common = static_library('flo-common', 'src/util.c', 'src/config.c')

sessiond = executable('flo-sessiond',
  'src/main.c', 'src/boost.c', 'src/freezer.c', 'src/server.c',
  link_with: common,
  install: true,
  install_dir: get_option('sbindir'),
)

subdir('tests')
