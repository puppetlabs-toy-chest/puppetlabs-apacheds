# What I want the interface to this module to actually look like.
class apacheds(
  $rootpw      = hiera('apacheds::rootpw'),
  $master_host = hiera('apacheds::master_host'),
  $port        = '10389',
  $ssl_port    = '10636',
  $parition_dn = hiera('apacheds::partition_dn'),
  $jks_pw      = hiera('apacheds::jks_pw'),
  $version,
  $master
) {

  class { 'java': distribution => 'jre' }

  package { 'apacheds':
    ensure  => $version,
    before  => File['/etc/apacheds'],
    require => Class['java'],
  }

  File { mode => '0644', owner => 'apacheds', group => 'root', }

  file { '/etc/apacheds':
    ensure => directory,
  }

  file { '/etc/apacheds/certs':
    ensure => directory,
    mode   => '0750',
    before => Java_ks[$::fqdn],
  }

  java_ks { 'ca':
    ensure      => latest,
    password    => $jks_pw,
    certificate => "/etc/apacheds/certs/${::fqdn}.pem",
    pirvate_key => "/etc/apacheds/certs/${::fqdn}.key",
    target      => "/var/lib/${version}/default/apacheds.jks",
    before      => Class['apacheds::config'],
    require     => Package['apacheds'],
  }

  java_ks { $::fqdn:
    ensure       => latest,
    password     => $jks_pw,
    certificate  => '/etc/apacheds/certs/ca.pem',
    target       => "/var/lib/${version}/default/apacheds.jks",
    trustcacerts => true,
    before       => Class['apacheds::config'],
    require      => Package['apacheds'],
  }

  if $master {

    # Master config
    class { 'apacheds::config':
      master          => true,  # Would be default
      port            => $port,
      ssl_port        => $ssl_port,
      use_ldaps       => true,
      jks             => 'apacheds.jks',
      jks_pw          => $jks_pw,
      partition_dn    => $parition_dn,
      allow_hashed_pw => true,  # Would be default
      version         => $version, # Yes this sucks but I don't want to repackage it.
      require         => Package['apacheds'],
    }

  } else {

    # Slave config
    class { 'apacheds::config':
      master          => false,
      master_host     => $master_host,
      port            => $port,
      ssl_port        => $ssl_port,
      use_ldaps       => true,
      jks             => 'apacheds.jks',
      partition_dn    => $parition_dn,
      allow_hashed_pw => true,
      version         => $version, # Yes this sucks but I don't want to repackage it.
      require         => Package['apacheds'],
    }
  }

  service { 'apacheds':
    name      => "apacheds-${version}-default",
    ensure    => running,
    enable    => true,
    subscribe => [ Package['apacheds'], Class['apacheds::config'], ],
  }
}
