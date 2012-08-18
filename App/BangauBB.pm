package BangauBB;
use 5.014;
use warnings;
use strict;
use base qw (CGI::Application);
use CGI::Application::Plugin::DBH (qw/dbh_config dbh/);
use CGI::Application::Plugin::Session;
use DateTime;
use URI::Find;
use CGI qw(escapeHTML);

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
        'create_thread_confirm' => 'create_thread_confirm_rm',
        'create_thread_post' => 'create_thread_post_rm',
        'view_thread' => 'view_thread_rm',
        'delete_thread' => 'delete_thread_rm',
        'delete_thread_post' => 'delete_thread_post_rm',
        
        #reply
        'create_reply' => 'create_reply_rm',
        'create_reply_confirm' => 'create_reply_confirm_rm',
        'create_reply_post' => 'create_reply_post_rm',
        'delete_reply' => 'delete_reply_rm',
        'delete_reply_post' => 'delete_reply_post_rm',
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
        $templRef->param('theme' => $self->query->param('theme'));
        $self->session->param('theme',$self->query->param('theme'));
    }elsif($self->session->param('theme')){
        $templRef->param('theme' => $self->session->param('theme'));
    }
    unless (defined $self->session->param('role')){
        $self->session->param('role', 'g');
    }
    given($self->session->param('role')){
        when('a'){
            $templRef->param('is_admin' => 'true');
            $templRef->param('role' => 'admin');
        }
        when('u'){
            $templRef->param('is_user' => 'true');
            $templRef->param('role' => 'user');
        }
        default {
            $templRef->param('is_guest' => 'true');
            $templRef->param('role' => 'guest');
        };
    }
    if($self->session->param('user')){
        $templRef->param('user' => $self->session->param('user'));
        $templRef->param('uid' => $self->session->param('uid'));
        return 1;
    }
    return 0;
}

sub filter_body_message{
    my $body = shift;
    my $finder = URI::Find->new(sub {
      my($uri, $orig_uri) = @_;
      return qq|<a href="$uri">$orig_uri</a>|;
    });
    $finder->find(\$body, \&escapeHTML);

    
    $body =~ s/(\S+@\S+\.\S+)(.+)/<a href=\"mailto:$1\">$1<\/a>/g;
    
    $body =~ s/\r\n/ <br\/> /g;
    $body =~ s/\n/ <br\/> /g;
    return $body;
    
}

sub upload_image{
    my $self = shift;
    my ($image, $name) = @_;
    my ($read, $data) = ();
    my $dest = $self->param('image_dir').$name;
    open (OUTPUT, ">", $dest) or die "Access denied: $dest";
    binmode OUTPUT;
    while(($read = read($image, $data, 512))!=0){
        print OUTPUT $data;
    }
    close OUTPUT;
}
sub delete_files{
    foreach $_(@_){
        unlink $_ or die "Can't delete file: $_ \n$!";
    }
}
sub print_debug(){
    my $s = "";
    #-- check if running as root
    $s.="Running as root!!\n" if ( $< == 0 );
     
    #-- print username
    $s.="Your username is " . (getpwuid($<))[0] . "\n";
     
    #-- print groups information
    my @groups = split '\s', $(;
    $s.="You belong to these groups: ";
    $s.= getgrgid($_) . " " foreach(@groups);
    $s.= "\n";
    die $s;
}
require('Membership.pl');
require('Topic.pl');
require('Thread.pl');
require('Reply.pl');

1;