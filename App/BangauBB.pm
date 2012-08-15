package BangauBB;
use 5.014;
use warnings;
use strict;
use MongoDB;
use base qw (CGI::Application);
use CGI::Application::Plugin::DBH (qw/dbh_config dbh/);
use CGI::Application::Plugin::Session;

sub setup{
    my $self = shift;
    $self->header_add(-charset => 'utf-8');
    $self->mode_param('rm');
    $self->run_modes(
        #Membership => Login, Logout, Register
        'login_post' => 'login_post_rm',
        #'logout' => 'logout_rm',
        'register' => 'register_rm',
        'register_post' => 'register_post_rm',
        'register_success' => 'register_success_rm',
        #service
        #'check_username' => 'is_username_available_rm'
        
        'home' => 'home_rm',
    );
    $self->start_mode('register');
}

sub cgiapp_init{
    my $self = shift;
    $self->query->charset('UTF-8');
    $self->dbh_config(
        $self->param('db_source'),
        $self->param('db_user'),
        $self->param('db_password'),
        $self->param('db_attr')
    );
    $self->dbh->do("SET NAMES 'utf8'");
    $self->session_config(
        CGI_SESSION_OPTIONS => [ "driver:File", $self->query, { Directory => '/tmp' } ],
        COOKIE_PARAMS => {
            -path  => '/',
            -expires => '+24h',
        },		
        SEND_COOKIE => 1,
    );
    $self->header_add( -charset => 'utf-8');
}

sub teardown {
    my $self = shift;
}

sub redirect{
    my $self = shift;
    $self->header_add(
      -location => $_[0]
    );
}

sub toDateTime{
    my $time = shift;
    if($time){
        my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime($time);
        return sprintf "%4d-%02d-%02d %02d:%02d:%02d\n",$year+1900,$mon+1,$mday,$hour,$min,$sec;
    }else{
        my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime;
        return sprintf "%4d-%02d-%02d %02d:%02d:%02d\n",$year+1900,$mon+1,$mday,$hour,$min,$sec;
    }
}

require('Membership.pl');

1;