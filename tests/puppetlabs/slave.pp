# What I want the interface to this module to actually look like.

class service::ldap::slave(
  $admin_dn         = 'uid=admin,ou=system',
  $admin_default_pw = 'secret',
  $admin_pw         = hiera('service::ldap::admin_pw'),
  $server           = $apacheds::master,
  $port             = $apacheds::port
) {

  class { 'apacheds': master => false, version => '2.0.0-M6' }

  Ads_entry {
    admin_dn         => $admin_dn,
    admin_pw         => $admin_pw,
    admin_default_pw => $admin_default_pw,
    server           => $server,
    port             => $port,
  }

  ads_entry { 'uid=admin':
    ensure     => present,
    attributes => { 'userPassword' => $admin_pw },
    require    => Class['apacheds'],
  }

  ads_entry { 'dc=puppetlabs,dc=net':
    ensure      => present,
    objectclass => [ 'dcObject', 'top', 'organization', 'administrativeRole' ],
    attributes  => { 'o' => 'Puppet Labs', 'administrativeRole' => 'accessControlSpecificArea' },
    require     => Ads_entry['uid=admin'],
  }
}
