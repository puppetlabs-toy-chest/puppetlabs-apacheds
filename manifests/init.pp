class apacheds(
  $master_host = hiera('apacheds::master_host'),
  $port        = '10389',
  $ssl_port    = '10636',
  $partition_dn = hiera('apacheds::partition_dn'),
  $jks         = '',
  $jks_pw      = '',
  $replica_id  = '1',
  $version,
  $master
) {

  class { 'java': distribution => 'jre' }

  group { 'apacheds':
    ensure => present,
    system => true,
  }
  user { 'apacheds':
    ensure     => present,
    system     => true,
    gid        => 'apacheds',
    managehome => false,
    home       => "/opt/apacheds-${version}",
  }

  package { 'apacheds':
    ensure  => $version,
    require => [ Class['java'], Class['apacheds::config'], User['apacheds'] ],
  }

  File { mode => '0644', owner => 'apacheds', group => 'root', }

  file { 'config.ldif':
    path    => "/var/lib/apacheds-${version}/default/conf/config.ldif",
    ensure  => symlink,
    target  => "/var/lib/apacheds-${version}/default/conf/config_puppet.ldif",
    force   => true,
    require => Package['apacheds'],
    notify  => Service['apacheds'],
  }

  if $master {

    # Master config
    class { 'apacheds::config':
      master_host     => $master_host,
      port            => $port,
      ssl_port        => $ssl_port,
      use_ldaps       => true,
      jks             => $jks,
      jks_pw          => $jks_pw,
      partition_dn    => $partition_dn,
      version         => $version, # Yes this sucks but I don't want to repackage it.
    }

  } else {

    # Slave config
    class { 'apacheds::config':
      master          => false,
      master_host     => $master_host,
      port            => $port,
      ssl_port        => $ssl_port,
      use_ldaps       => true,
      jks             => $jks,
      jks_pw          => $jks_pw,
      partition_dn    => $partition_dn,
      version         => $version
    }
  }

  # Init script is broken, always returns zero
  service { 'apacheds':
    name      => "apacheds-${version}-default",
    ensure    => running,
    enable    => true,
    hasstatus => false,
    pattern   => "java.*apacheds-${version}.*",
    subscribe => Package['apacheds'],
  }
}
