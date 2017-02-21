#!/usr/bin/perl
#
#   scriptname - vendor_scribe_display.pl_1
#
#   Web page to allow input of lot number(s) to list Vendor Scribe.
#
#   2010-01-28 Skip Mencio
#   2012-09-05 Skip Mencio -- Added note that '%' can be used as a wild card character
#

BEGIN {
   @path=split(/\//,$0);
   pop(@path);
   $path=join('/',@path);
   push(@INC,$path);
}

use strict;
#use warnings;

use DBI;
use CGI;

use vendor_scribe_display;

# Get web input.

my $INPUT=new CGI;

my %INPUT = map {$_ => $INPUT->param($_) } $INPUT->param;
#my %INPUT;
#$INPUT{select}="InHouse";
#$INPUT{lotid}="TT74075";
#$INPUT{stage}="2794SLTH";

# Get today's date/time for use as distinct file label.

chomp(my $dt=`date +"%Y%m%d%H%M%S"`);

# IF no input, create web entry page.

unless($INPUT{select}){

   print "Content-type: text/html\n\n";

# Set web page header.

   print "<html>\n";
   &freescale_header("In-House and Vendor Scribe Correlation and Wafer Sort Order");
   print "<header>\n";
   print "   <title>In-House and Vendor Scribe Correlation and Wafer Sort Order</title>\n";
   print "</header>\n";

   print "<body bgcolor=\042#FFFFFF\042>\n";
   print "<center><h2>In-House and Vendor Scribe Correlation and Wafer Sort Order<br></h2>\n";
   print "<br><br>\n";

# Get user input.

   print "
   <center>\n
   <table width=100%>
   <tr align=center><td>
   Enter <b>IN-HOUSE</b> lot number(s) to determine Vendor Scribes to be retrieved.<br>\n
   The lot extension is not necessary.<br>\n
   Use '%' as a wild card character.<br>\n

   <form name=form1 method=POST action=$script_web_dir/bin/$script_name>\n
   <input type=hidden name=select value=InHouse>
   <TEXTAREA name=lotid rows = 5 cols=15></TEXTAREA>\n
   <br><br><input type=\042submit\042 value=\042Get Vendor Scribe Data\042>\n
   </form>\n

   <td>
   Enter <b>VENDOR</b> number(s) to determine In-House lot numbers to be retrieved.<br>\n
   Use '%' as a wild card character.<br>\n
   <form name=form2 method=POST action=$script_web_dir/bin/$script_name>\n
   <input type=hidden name=select value=Vendor>
   <TEXTAREA name=lotid rows=5 cols=20></TEXTAREA>\n
   <br><br><input type=\042submit\042 value=\042Get In-House Scribe Data\042>\n
   </form>

   <tr><td align=center colspan=2>
   </table>\n";
   
   &freescale_footer($contact,$contact_email,$dt,$modification_date);
   print "</body>\n";
   print "</html>\n";

} #unless($INPUT{select})   Closes data entry web page.

#   Enter <b>IN-HOUSE</b> lot number(s) to determine pre and post sorter data.<br>Lot extension is not necessary<br>\n
#   <form name=form3 method=POST action=$script_web_dir/bin/$script_name>\n
#   <input type=hidden name=select value=SortStage>
#   <input type=text name=lotid>\n
#   <br><br><input type=\042submit\042 value=\042Get Pre - Post Sort Order\042>\n
#   </form>

# Display vendor scribe info given in-house scribe info.

if ($INPUT{select} =~ /InHouse|Vendor/){

   print "Content-type: text/html\n\n";

# Set script variables.

   my $data_exists_flag=0;
   my $output_filename="tmp_lotnum_".$dt.".xls";

   $INPUT{lotid}="\U$INPUT{lotid}";

# Consolidate multiple lots into list.

   my ($lotlist,@lotlist,@lotlist1,@dummy);
   @lotlist=split(/\s+/,$INPUT{lotid});
   foreach my $lot (@lotlist){
      @dummy=split(/\./,$lot);
      push @lotlist1,"$dummy[0]";
   }

# Print web page and table header.

   print "<html>\n";

   &freescale_header("In-House and Vendor Scribe Correlation");

   print "
   <title>In-House and Vendor Scribe Correlation</title>
   <body><br><h2><center>In-House and Vendor Scribe Correlation</center></h2><br>

   <a href=$output_web_dir/$output_filename>Excel DownLoad</a><br>

   <table border=1 align=center>
      <tr bgcolor=\042#CC99CC\042>
         <td>Lot Number</td><td>Wafer Number</td><td>Vendor Scribe</td><td>Scribe Date</td>
      </tr>\n";

# Open file for data download.

   open(OFH,">$output_data_dir/$output_filename");

   print OFH "Source Lot Number\tWafer Number\tVendor Scribe\tScribe Date\n";

# Get scribe info from database.

   my (%scribe_data,%scribe_date);
   my ($scribe_data,$scribe_date);

   ($scribe_data,$scribe_date,$data_exists_flag)=&get_scribe_data($db_factory,$db_name,$INPUT{select},\@lotlist1);

   %scribe_data=%$scribe_data;
   %scribe_date=%$scribe_date;

# Display scribe info on web page.

   if ($data_exists_flag){
      foreach my $lotid(sort keys %scribe_data){
         my $full_lotid=&checklot($lotid);
         foreach my $wfr_num (sort keys %{$scribe_data{$lotid}}){
	    print "<tr><td>$full_lotid</td><td>$wfr_num</td><td>$scribe_data{$lotid}{$wfr_num}</td><td>$scribe_date{$lotid}</tr>\n";
	    print OFH "$full_lotid\t$wfr_num\t$scribe_data{$lotid}{$wfr_num}\t$scribe_date{$lotid}\n";
	    }
         }
      }
   else{
      print "<tr><td colspan=3>Lot(s) $lotlist do not have $INPUT{select} Scribe information in the database.</td></tr>";
      }

   print "</table>\n";

   print "</form>\n";
   &freescale_footer($contact,$contact_email,$dt,$modification_date);
   print "</body></html>\n";

   close OFH;

   chmod(0777,"$output_data_dir/$output_filename");

} # End if($INPUT{select} =~ "/InHouse|Vendor/")

# Display stage info for given in-house scribe.

if ($INPUT{select} =~ /SortStage/){

   print "Content-type: text/html\n\n";

# Remove extension from lot number if it exists.

   my @dummy=split(/\./,$INPUT{lotid});
   $INPUT{lotid}=$dummy[0];

# Print web page and table header.

   print "<html>\n";

   &freescale_header("Time Order Stage List");

   print "

   <title>Time Order Stage List</title>
   <body><br><h2><center>Time Order Stage List for Lot $INPUT{lotid}</center></h2><br>

   <br><center>Select Stage <B>IMMEDIATELY AFTER</B> stage of interest</center><br>

   <form method=POST action=$script_web_dir/bin/$script_name>

   <input type=hidden name=lotid value=$INPUT{lotid}>
   <input type=hidden name=select value=SortSlot>

   <table border=1 align=center>
   <tr bgcolor=\042#CC99CC\042>
   <td>Lot Number</td><td>Stage List</td>
   </tr>\n";

# Get stage list info.

   my $dbh = DBI->connect(&getconn($db_factory,$db_name)) || die "Database connection to $db_factory $db_name not made: $DBI::errstr\n";

   my $select="SELECT source_lot, stage, to_char(read_date,'YYYYMMDDHH24MISS') ";
   my $from  ="FROM $tbl_owner.wafer_sort_table ";
   my $where="WHERE (source_lot = '$INPUT{lotid}') ";
   my $sql=$select.$from.$where;

   my $sth=$dbh->prepare($sql);
   my($source_lot,$stage,$read_date,%stage_order);
   my $data_exists_flag=0;

   $sth->execute();
   $sth->bind_columns(undef,\$source_lot,\$stage,\$read_date);
   while($sth->fetch()){
      $data_exists_flag=1;
      $stage_order{$read_date}=$stage;
   }
   $sth->finish();
   $dbh->disconnect();

# Display stage info on web page.

   if ($data_exists_flag){
      print "
      <tr>
      <td>$INPUT{lotid}</td>
      <td><select name=stage>
      \n";
      foreach my $date(sort keys %stage_order){
         print "
         <option value='$stage_order{$date}'>$stage_order{$date}\n";
      }
      print "</select></td></tr>\n";
   }else{
      print "
      <tr><td colspan=2>Lot $INPUT{lotid} does not have any data in the database</td></tr>\n";
   }

   print "</table>\n";

   print "<br><br><center><input type=\042submit\042 value=\042Get Sort Data\042></center>\n";

   print "</form>\n";
   &freescale_footer($contact,$contact_email,$dt,$modification_date);
   print "</body></html>\n";

} #End if ($INPUT{select} =~ /SorterStage/){

# Extract pre and post sorter data and display.

if ($INPUT{select} eq "SortSlot"){

   print "Content-type: text/html\n\n";

   my $output_filename="tmp_lotnum_".$dt.".xls";

# Print web page and table header.

   print "<html>\n";

   &freescale_header("Time Order Stage List");

   print "

   <title>Post/Pre Sort Order Comparison</title>
   <body><br><h2><center>Post/Pre Sort Order Comparison</center></h2><br>

   <a href=$output_web_dir/$output_filename>Excel DownLoad</a><br>

   <table border=1 align=center>
   <tr bgcolor=\042#CC99CC\042>
   <td>Source Lot Number<td>Wafer Number<td>Vendor Scribe<td>Stage<td>Post Sort Order<td>Stage<td>Pre Sort Order\n";

# Open file for data download.

   open(OFH,">$output_data_dir/$output_filename");

   print OFH "Source Lot Number\tWafer Number\tVendor Scribe\tStage\tPost Sort Order\tStage\tPre Sort Order\n";

# Get vendor scribe info from MID.

   my $dbh = DBI->connect(&getconn($db_factory,$db_name)) || die "Database connection to $db_factory $db_name not made: $DBI::errstr\n";

   my $select="SELECT w2s_source_lot, w2s_wafer_num, w2s_vendor_scribe ";
   my $from  ="FROM $tbl_owner.be_scribe_correlation ";
   my $where="WHERE (source_lot like '$INPUT{lotid}') ";
   my $sql=$select.$from.$where;
   my $sth=$dbh->prepare($sql);
   my ($source_lot,$wafer_num,$vendor_scribe,%vendor_scribe_data);

   $sth->execute();
   $sth->bind_columns(undef,\$source_lot,\$wafer_num,\$vendor_scribe);
   while($sth->fetch()){
      $vendor_scribe_data{$source_lot}{$wafer_num}=$vendor_scribe;
   }
   $sth->finish();

# Get sort info from MID.

   my $data_exists_flag=0;
   $select="SELECT w2s_source_lot, w2s_wafer_num, w2s_stage, w2s_previous_slot, w2s_post_slot, to_char(w2s_read_date,'YYYYMMDDHH24MISS') ";
   $from  ="FROM $tbl_owner.be_wafer_ord ";
   $where="WHERE (source_lot like '$INPUT{lotid}') ";
   $sql=$select.$from.$where;

   $sth=$dbh->prepare($sql);
   my ($stage,$pre_slot,$post_slot,$read_date,%stage_order,%scribe_data);

   $sth->execute();
   $sth->bind_columns(undef,\$source_lot,\$wafer_num,\$stage,\$pre_slot,\$post_slot,\$read_date);
   while($sth->fetch()){
      $data_exists_flag=1;
      $stage_order{$read_date}=$stage;
      $scribe_data{$source_lot}{$stage}{$wafer_num}{pre}=$pre_slot;
      $scribe_data{$source_lot}{$stage}{$wafer_num}{post}=$post_slot;
   }
   $sth->finish();
   $dbh->disconnect();

# Display scribe info on web page.
# Output will be the post slot from the previous stage and the pre slot from the selected stage.  This will allow slot order integrity comparison.

   if ($data_exists_flag){
      my $old_stage="";
      foreach my $read_date (sort keys %stage_order){
         if ($stage_order{$read_date} eq $INPUT{stage}){
            my $stage=$stage_order{$read_date};
            foreach my $lot_id (sort keys %scribe_data){
               foreach my $wafer_num (sort keys %{$scribe_data{$lot_id}{$stage}}){
                  my $old_stage_slot=$scribe_data{$lot_id}{$old_stage}{$wafer_num}{post};
                  my $stage_slot=$scribe_data{$lot_id}{$stage}{$wafer_num}{pre};
                  print "<tr><td>$lot_id<td>$wafer_num<td>$vendor_scribe_data{$lot_id}{$wafer_num}<td>$old_stage";
                  print "<td>$old_stage_slot<td>$stage<td>$stage_slot\n";
                  print OFH "$lot_id\t$wafer_num\t$vendor_scribe_data{$lot_id}{$wafer_num}\t$old_stage\t$old_stage_slot\t$stage\t$stage_slot\n";
               }
            }
         }
         $old_stage=$stage_order{$read_date};
      }
   }else{
      print "<tr><td colspan=7>Lot $INPUT{lotid} does not have Sort data stored in the database</td><tr>";
   }

   print "</table>\n";

   print "</form>\n";
   &freescale_footer($contact,$contact_email,$dt,$modification_date);
   print "</body></html>\n";

   close OFH;

   chmod(0777,"$output_data_dir/$output_filename");

} #End if($INPUT{select} eq "SortSlot")








