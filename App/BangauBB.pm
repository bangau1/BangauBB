package BangauBB;
use 5.014;
use warnings;
use strict;
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
        'logout' => 'logout_rm',
        'register' => 'register_rm',
        'register_post' => 'register_post_rm',
        'register_success' => 'register_success_rm',
        #service
        #'check_username' => 'is_username_available_rm'
        
        'home' => 'home_rm',
        
        #topics
        'create_topic' => 'create_topic_rm',
        'create_topic_post' => 'create_topic_post_rm',
        'view_topic' => 'view_topic_rm',
        
        #thread
        'create_thread' => 'create_thread_rm',
        'create_thread_post' => 'create_thread_post_rm',
        'view_thread' => 'view_thread_rm',
    );
    $self->start_mode('home');
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

sub passCredential_Session{
    my $self = shift;
    my $templRef = shift;
    #apply theme from param
    if($self->query->param('theme')){
        ${$templRef}->param('theme', $self->query->param('theme'));
        $self->session->param('theme',$self->query->param('theme'));
    }elsif($self->session->param('theme')){
        ${$templRef}->param('theme', $self->session->param('theme'));
    }
    
    if($self->session->param('user')){
        ${$templRef}->param('user', $self->session->param('user'));
        ${$templRef}->param('role', $self->session->param('role'));
        ${$templRef}->param('uid', $self->session->param('uid'));
        given($self->session->param('role')){
            when('a'){ ${$templRef}->param('is_admin', 'true')}
            when('u'){ ${$templRef}->param('is_user', 'true')}
            when('g'){ ${$templRef}->param('is_guest', 'true')}
        }
        return 1;
    }
    
    return 0;
}

require('Membership.pl');
require('Topic.pl');

1;