#!/usr/local/bin/perl5
use Net::LDAP;
use Exporter;
##########################################################################################################
#  This is a package use about AD,3 major function:
#  1:return mail address: my $mail=&getmail(nxa22005,nxa22006,nxa22007);
#  2:do authentication: my $result=&authentication(nxa22005,******);
#  3:query personal default info or input attribute:my @info=&getinfo("nxa22005,nxa22006",'cn'); my $info_ref=$info[0]; my %info=%$info_ref;
#  Author:LiuZX 2016 11
#########################################################################################################
@ISA=qw(Exporter);
@EXPORT=qw(&getmail &authentication &getinfo);
my $ldaps_url="ldap://US1PH84DC201v.wbi.nxp.com";
my $base="DC=wbi,DC=nxp,DC=com";
my $service_dn = "CN=probeappad,OU=SRV Accounts,OU=Accounts,OU=Service Delivery,DC=wbi,DC=nxp,DC=com";
my $service_password="Passw0rd";
sub getmail{
	my $account=shift;
	my @account=split (/(,|;)/,$account);
	my $attributes = "mail";
	my $filter;
	my @mail;
	foreach my $string (@account){
		$filter.="(samaccountname =$string)"
	}	
	$ldap = Net::LDAP->new( $ldaps_url,"LDAP_OPT_REFERRALS" => 0 , "LDAP_OPT_PROTOCOL_VERSION" => 3 ) or die "999:$! ($@)\n";
	$mesg =$ldap->bind( $service_dn, password => $service_password ) or die $!;
	$results = $ldap->search(
                          base  =>$base,
                          filter =>"(|$filter)",
                          attrs =>[$attributes]
                        );
	@msg=$results->entries;
	my %output;
	foreach my $search(@msg){
        	$output{mail}=$search->get_value('mail');
		push @mail,$output{mail};
	}
	$ldap->unbind;
	return join(",",@mail);
}
sub authentication{
        my $account=shift;
        my $password=shift;
        my $filter="samaccountname=$account";
        $ldap = Net::LDAP->new( $ldaps_url,"LDAP_OPT_REFERRALS" => 0 , "LDAP_OPT_PROTOCOL_VERSION" => 3 ) or die "999:$! ($@)\n";
        $mesg =$ldap->bind( $service_dn, password => $service_password ) or die $!;
        $results = $ldap->search(
                          base  =>$base,
                          filter =>"($filter)",
                          attrs =>["distinguishedName"]
                        );
        @msg=$results->entries;
        my %output;
        foreach my $search(@msg){
                $output{dn}=$search->get_value('distinguishedName');
        }
        $bind = $ldap->bind( $output{dn}, password => "$password" ) or die $!;
        $ldap->unbind;
        if ($output{dn} ne ""){
                return join(":",$bind->code,$bind->error);
        }else{
                return join(":","1","invaild account");
        }
}
sub getinfo{
	my $account=shift;
	my $attribute=shift;
	my @account=split (/(,|;)/,$account);
        foreach my $string (@account){
                $filter.="(samaccountname =$string)"
        }
	$attribute="displayName,postOfficeBox,cn,mail,telephoneNumber" if ($attribute eq "");
	my @attribute=split(/,/,$attribute);
	$ldap = Net::LDAP->new( $ldaps_url,"LDAP_OPT_REFERRALS" => 0 , "LDAP_OPT_PROTOCOL_VERSION" => 3 ) or die "999:$! ($@)\n";
        $mesg =$ldap->bind( $service_dn, password => $service_password ) or die $!;
                $results = $ldap->search(
                          base  =>$base,
                          filter =>"(|$filter)",
                          attrs =>\@attribute
                        );
        @msg=$results->entries;
        my @output;
        foreach my $search(@msg){
		my %output;
		foreach my $string (@attribute){
                	$output{$string}=$search->get_value($string);
		}
		push @output,\%output;
        }
        $ldap->unbind;
	return @output;
}
1
