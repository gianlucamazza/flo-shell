unitdir = get_option('systemdsystemunitdir')
if unitdir == ''
  unitdir = get_option('prefix') / 'lib' / 'systemd' / 'system'
endif

conf = configuration_data()
conf.set('sbindir', get_option('prefix') / get_option('sbindir'))
conf.set('socket_group', get_option('socket_group'))

configure_file(input: 'flo-sessiond.service.in', output: 'flo-sessiond.service',
  configuration: conf, install_dir: unitdir)
configure_file(input: 'flo-sessiond.socket.in', output: 'flo-sessiond.socket',
  configuration: conf, install_dir: unitdir)
configure_file(input: 'flo-sessiond.sysusers.in', output: 'flo-sessiond.conf',
  configuration: conf, install_dir: get_option('prefix') / 'lib' / 'sysusers.d')

if get_option('install_config')
  install_data('flo-sessiond.conf', install_dir: get_option('sysconfdir'))
endif
