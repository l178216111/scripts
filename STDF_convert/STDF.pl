#!usr/bin/perl 
use Data::Dumper;
my $STDF_dir="c:\\Users\\b44697\\STDF";
die "couldn't locate stdf.dll in $STDF_dir\n"unless(-e "$STDF_dir\\stdf.dll");
die "couldn't locate stdfatdf.exe in $STDF_dir\n"unless(-e "$STDF_dir\\stdfatdf.exe");
die "couldn't locate atdfstdf.exe in $STDF_dir\n"unless(-e "$STDF_dir\\atdfstdf.exe");
my $dir = $1 if $ARGV[0]=~ /^(.+)$/;
my $name = $1 if $ARGV[1]=~ /^(.+)$/;
unless(-d "$dir\\temp"){
mkdir("$dir\\temp")||die "couldn'd make  dir $dir\temp: $!\n";
}
unless(-d "$dir\\done"){
mkdir("$dir\\done")||die "couldn'd make  dir $dir\done: $!\n";
}
opendir(STDF,$dir)||die "couldn'd open dir $Path: $!\n";
my @files=readdir(STDF);
my $files_num=@files;
closedir STDF;
for my $modify (sort @files){
	unless($modify=~ /.stdf$/){
	$files_num--;
	next;
	}
	my $file_name=$1 if $modify=~ /(.*)\.stdf$/;
	system("cd $STDF_dir&&stdfatdf $dir\\$modify $dir\\temp\\$file_name.stdf");
    open (OUTFILE,">","$dir\\temp\\$file_name.atdf")||die"Can't write the STDF: $!\n";
	open(FILE,"<","$dir\\temp\\$file_name.stdf")||die"Can't open the file: $!\n";
	my $index=0;
		while($line=<FILE>){
		if ($index==1){
		my $string = (  split '\|', $line )[1];
		$line=~ s/$string/$name/;
		#print "$line";
		}
		$index++;
		print OUTFILE "$line";
		}
	close FILE;
	close OUTFILE;
	system("cd c:\\Users\\b44697\\STDF&&atdfstdf $dir\\temp\\$file_name.atdf $dir\\done\\$modify");
	print "$modify converted done\n";
}
print "###################################################################\n";
print "Convert STDF files total:$files_num\n";
print "Removing tempfile:  $dir\\temp\n";
print "Program running done\n";
print "###################################################################";
system("rd/s/q $dir\\temp");