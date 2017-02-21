
use DBI;
use Exporter;
@ISA=qw(Exporter);
@EXPORT=qw(
  &getconn
  &getoraenv
  &setoraenv
);


# TJN database
  $connection{'tjn'}{'promis'}{'read'}=[('dbi:Oracle:tjnptor','probe','ProbeAppsWeb')];
  $connection{'tjn'}{'genesis'}{'read'}=[('dbi:Oracle:tjndss11g','probe','probeappsweb')];
  $connection{'tjn'}{'jbstar'}{'readwrite'}=[('dbi:Oracle:m17pmis1','jbstar_loader','jbstarloader')];
  $connection{'tjn'}{'probeweb'}{'readwrite'}=[('dbi:Oracle:m17pmis1','probeweb','probeweb')];

# Other site database
  $connection{'ATMC'}{'promis'}{'read'}=[('dbi:Oracle:dncptor','probeweb','probeweb01')];
  $connection{'OHT-FAB'}{'promis'}{'read'}=[('dbi:Oracle:ohtptor','readonly','readonly')];
  $connection{'CHD-FAB'}{'promis'}{'read'}=[('dbi:Oracle:chdptor','probeweb','probeweb01')];
  $connection{'EKB-FAB'}{'promis'}{'read'}=[('dbi:Oracle:ekbptor','probeweb','probeweb01')];
  $connection{'TLS-FAB'}{'promis'}{'read'}=[('dbi:Oracle:tlsptor','probeweb','probewebapps')];
  $connection{'SND-FAB'}{'promis'}{'read'}=[('dbi:Oracle:sndptor','probeweb','probeweb01')];
  $connection{'klm'}{'promis'}{'read'}=[('dbi:Oracle:klmptor','probeweb','probeweb01')];

# return the DBI connecting string
sub getconn {
  my ($db,$site,$perm,$ac,$pe,$re)=@_;
  my %subhash=();
  if (defined $ac){
    $subhash{AutoCommit}=$ac;
  } else {
    $subhash{AutoCommit}=1;
  }
  if (defined $re){
    $subhash{RaiseError}=$re;
  } else {
    $subhash{RaiseError}=1;
  }
  if (defined $pe){
    $subhash{PrintError}=$ac;
  } else {
    $subhash{PrintError}=1;
  }
  if (! defined $perm){
    $perm='readwrite';
  }
  if (defined $connection{$db}{$site}{$perm}){
    my @conn=@{$connection{$db}{$site}{$perm}};
    push(@conn,\%subhash);
    return @conn
  } else {
    warn "Database Connection to DB: $db for $site not found in config file\n";
    return ();
  }
}

#---------------------------------------------------------------------------------------
# return ORACLE ENV array
sub getoraenv {
	my %oraenv;
	$oraenv{ORACLE_HOME}=$ENV{ORACLE_HOME} if ( defined $ENV{ORACLE_HOME} );
	$oraenv{PATH}=$ENV{PATH} if ( defined $ENV{PATH} );
	$oraenv{TWO_TASK}=$ENV{TWO_TASK} if ( defined $ENV{TWO_TASK} );
	$oraenv{NLS_LANG}=$ENV{NLS_LANG} if ( defined $ENV{NLS_LANG} );
  return %oraenv;
}

#---------------------------------------------------------------------------------------
# set custom ORACLE ENV
sub setoraenv {
  my %custENV=@_;
  $ENV{ORACLE_HOME}=$custENV{ORACLE_HOME} if ( defined custENV{ORACLE_HOME} );
  $ENV{PATH}=$ENV{PATH}.";".$custENV{PATH} if ( defined custENV{PATH} );
  $ENV{TWO_TASK}=$custENV{TWO_TASK} if ( defined custENV{TWO_TASK} );
  $ENV{NLS_LANG}=$custENV{NLS_LANG} if ( defined custENV{NLS_LANG} );
}

1;
