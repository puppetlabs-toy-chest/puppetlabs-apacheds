# What I want the interface to this module to actually look like.
class service::ldap::master(
  $admin_dn           = 'uid=admin,ou=system',
  $admin_default_pw   = 'secret',
  $admin_pw           = hiera('service::ldap::admin_pw'),
  $server             = $apacheds::master,
  $port               = $apacheds::port,
  $directory_managers = hiera('service::ldap::directory_managers'),
) {

  class { 'apacheds': master => true, version => '2.0.0-M6' }

  Ads_entry {
    admin_dn         => $admin_dn,
    admin_pw         => $admin_pw,
    server           => $server,
  }

  ads_entry { 'uid=admin,ou=system':
    ensure     => present,
    attributes => { 'userPassword' => $admin_pw },
    require    => Class['apacheds'],
  }

  ads_entry { 'cn=nis,ou=schema':
    ensure => present,
    attributes => [ 'm-disabled' => 'FALSE' ],
    require    => Ads_entry['uid=admin,ou=system'],
  }

  ads_entry { 'dc=puppetlabs,dc=net':
    ensure       => present,
    objectclass  => [ 'dcObject', 'top', 'organization', 'administrativeRole' ],
    attributes   => { 'o' => 'Puppet Labs', 'administrativeRole' => 'accessControlSpecificArea' },
    require      => Ads_entry[[ 'uid=admin,ou=system', 'cn=nis,ou=schema' ]],
  }

  ads_entry { 'ou=people,dc=puppetlabs,dc=net':
    ensure       => present,
    objectclass  => [ 'dcObject', 'top', 'organizationalUnit' ],
    attributes   => { 'ou' => 'people',  },
    require      => Ads_entry['dc=puppetlabs,dc=net'],
  }

  ads_entry { 'ou=group,dc=puppetlabs,dc=net':
    ensure       => present,
    objectclass  => [ 'top', 'organizationalUnit' ],
    attributes   => { 'ou' => 'group', },
    require      => Ads_entry['dc=puppetlabs,dc=net'],
  }

  ads_entry { 'ou=automount,dc=puppetlabs,dc=net':
    ensure       => present,
    objectclass  => [ 'top', 'organizationalUnit' ],
    attributes   => { 'ou' => 'automount', },
    require      => Ads_entry['dc=puppetlabs,dc=net'],
  }

  $dir_manager = template("${module_name}/dir_managers_ldif.erb")
  $default_all_users = template("${module_name}/default_all_users_ldif.erb")
  $self_access = template("${module_name}/self_acces_ldif.erb")

  ads_entry { 'cn=puppetlabsACISubentry,dc=puppetlabs,dc=net':
    ensure      => present,
    objectclass => [ 'accessControlSubentry', 'top', 'subentry' ],
    attributes  => {
      'cn'              => 'puppetlabsACISubentry',
      'prescriptiveACI' => $dir_managers,
      'prescriptiveACI' => $default_all_users,
      'prescriptiveACI' => $self_access,
    },
    require      => Ads_entry['dc=puppetlabs,dc=net'],
  }
}

