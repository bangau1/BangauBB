#!/usr/bin/perl -w
use strict;
use utf8;
use 5.014;
use CGI::Carp qw(fatalsToBrowser warningsToBrowser set_message);
use lib qw(
    /home/agung/BangauBB/App
    /home/agung/perl5/lib/perl5/x86_64-linux-gnu-thread-multi
    /home/agung/perl5/lib/perl5
    /etc/perl
    /usr/local/lib/perl/5.14.2
    /usr/local/share/perl/5.14.2
    /usr/lib/perl5
    /usr/share/perl5
    /usr/lib/perl/5.14
    /usr/share/perl/5.14
    /usr/local/lib/site_perl
);
use BangauBB;

BEGIN{
    sub handle_errors{
        my $msg = shift;
        print "<h1>Oh sh*t</h1>";
        print "<p>Got an error: $msg</p>";
    }
    set_message(\&handle_errors);
}

my $board = BangauBB->new(
    TMPL_PATH => '/home/agung/BangauBB/template/',
    PARAMS => {
        'db_hostname' => 'localhost',
        'db_port' => '27017',
        'db_user' => 'root',
        'db_password' => 'root',
        'db_attr' => { mysql_enable_utf8 => 1, RaiseError => 1, AutoCommit => 0 },
        'db_source' => 'DBI:mysql:database=bangaubb;host=localhost;port=3306',
        'image_dir' => '/home/agung/BangauBB/image_dir/',
    }
);

$board->run();