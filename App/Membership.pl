#service
use strict;
use Digest::SHA qw(sha1 sha1_hex sha1_base64);
use DBI;

#register
sub register_rm{
    my $self = shift;
    my $tmpl = $self->load_tmpl('membership/register.tmpl',  die_on_bad_params => 0);
    $tmpl->param(
        breadcrumbs => [
            { name => "Home", link=>"./index.pl?rm=home"},
            { name => "Register", link=>"./index.pl?rm=register", active=>"true"},
        ]
    );
    if($self->passCredential_Session(\$tmpl)){
       $self->redirect('./index.pl?rm=home');
    }else{
        return $tmpl->output();    
    }
}

sub register_post_rm{
    my $self = shift;
    my $q = $self->query();
    my ($username, $password, $role) = ($q->param('username'), $q->param('password'), $q->param('role'));
    my $status = 0;
    if($username && $password && $role 
       && $q->param('confirmed_password') eq $password
       && length $username >= 4 && length $username <= 12){
       my $stmt = $self->dbh->prepare("INSERT INTO users(role, username, password, date_created) VALUES (?,?,?,?)")
            or die "Couldn't prepare statement : ".$self->dbh->errstr;
       my $dateTime = &toDateTime;
       
       $status = $stmt->execute(substr(lc $role, 0,1), $username, sha1_base64($password.$username),$dateTime);
       $self->dbh->commit();
    }
    if($status){
        my $insertId = $self->dbh->selectrow_array("SELECT LAST_INSERT_ID()") or die $self->dbh->errstr;
        $self->session->param('uid', $insertId);
        $self->session->param('user', $username);
        $self->session->param('role', lcfirst $role);
        $self->redirect('./index.pl?rm=home');
    }else{
        $self->redirect("./index.pl?rm=register")
    }
    return;
}

sub register_success_rm{

}

#login
sub login_post_rm{
    my $self = shift;
    my $q = $self->query();
    my ($username, $password) = ($q->param('username'), $q->param('password'));
    my ($role, $id) = (undef,undef);
    if($username && $password){
        my @ret = $self->dbh->selectrow_array("SELECT id, role FROM users WHERE username = ? and password = ?", {},
                                              ($username, sha1_base64($password.$username))) or die;
        $role = $ret[1];
        $id = $ret[0];
    }
    if($id){
        $self->session->param('user', $username);
        $self->session->param('role', lcfirst $role);
        $self->session->param('uid', $id);
        $self->redirect("?rm=home");
    }else{
        $self->redirect("?rm=error");
    }
}
#logout
sub logout_rm{
    my $self = shift;
    $self->session->clear();
    $self->redirect("./index.pl?rm=home");
}


1;