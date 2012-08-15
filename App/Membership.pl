#service
use Digest::SHA qw(sha1 sha1_hex sha1_base64);
use DBI;

#register
sub register_rm{
    my $self = shift;
    my $tmpl = $self->load_tmpl('membership/register.tmpl');
    $tmpl->param(
        breadcrumbs => [
            { name => "Home", link=>"./index.pl?rm=home"},
            { name => "Register", link=>"./index.pl?rm=register", active=>"true"},
        ]
    );
    if($self->session->param('user')){
        $self->redirect('./index.pl?rm=home');
    }else{
        return $tmpl->output();    
    }
}

sub register_post_rm{
    my $self = shift;
    my $q = $self->query();
    my ($username, $password, $role) = ($q->param('username'), $q->param('password'), $q->param('role'));
    
    if($username && $password && $role 
       && $q->param('confirmed_password') eq $password
       && length $username >= 4 && length $username <= 12){
        
       $stmt = $self->dbh->prepare("INSERT INTO users(role, username, password, date_created) VALUES (?,?,?,?)") or die;
       $dateTime = toDateTime;
       
       $status = $stmt->execute(substr(lc $role, 0,1), $username, sha1_base64($password.$username),$dateTime);
       $self->dbh->commit();
    }
    if($status){
        $self->session->param('user', $username);
        $self->session->param('role', $lcf )
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
    
}

#home
sub home_rm{
    my $self = shift;
    my $tmpl = $self->load_tmpl('membership/home.tmpl');
    
    if($self->session->param('user')){
        $tmpl->param('user', $self->session->param('user'));
    }
    
    $tmpl->param(
        breadcrumbs => [
            { name => "Home", link=>"./index.pl?rm=home", active=>"true"},
        ]
    );
    return $tmpl->output();
}
1;