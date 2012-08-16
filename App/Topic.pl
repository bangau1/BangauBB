#service
use strict;
use Digest::SHA qw(sha1 sha1_hex sha1_base64);
use DBI;

sub getSortedTopicsForHomePage{
    my $self = shift;
    my $from = shift;
    my $limit = shift;
    
    if(not defined $from){
        $from = 0;
    }
    if(not defined $limit){
        $limit = 10;
    }
    
    my $stmt = $self->dbh->prepare("
    SELECT t.id as topic_id, t.title as topic_title, thread_id, username as user, thread_title, date_modified
    FROM topics t left outer join 
    (
        select td.topic_id as topic_id, td.id as thread_id, td.title as thread_title, u.username as username, td.date_modified as date_modified
        from threads td, users u
        where  td.creator_id = u.id 
        order by date_modified DESC
    ) p
    ON p.topic_id = t.id
    ORDER BY date_modified DESC
    LIMIT $from, $limit
    ") or die $self->dbh->errstr;
    $stmt->execute();
    
    my @rows = ();
    push @rows, $_ while $_ = $stmt->fetchrow_hashref();
    return @rows;
}
#home_page
sub home_rm{
    my $self = shift;
    my $tmpl = $self->load_tmpl('membership/home.tmpl',  die_on_bad_params => 0);
    
    $self->passCredential_Session(\$tmpl);
    
    $tmpl->param(
        breadcrumbs => [
            { name => "Home", link=>"./index.pl?rm=home", active=>"true"},
        ]
    );
    my @rows = $self->getSortedTopicsForHomePage(0, 10);
    $tmpl->param(topics => \@rows);
    return $tmpl->output();
}

#create topic
sub create_topic_rm{
    my $self = shift;
    my $tmpl = $self->load_tmpl('post/create_topic.tmpl', die_on_bad_params => 0);
    if($self->session->param('role') eq 'a' && $self->passCredential_Session(\$tmpl)){
       return $tmpl->output();
    }else{
        $self->redirect("./index.pl?rm=home");   
    }
}

#create topic (data POST)
sub create_topic_post_rm{
    my $self = shift;
    my $title = $self->query->param('title');
    my $dateTime = &toDateTime;
    my $status = undef;
    #just admin can create new topic
    if($title && $self->session->param('role') eq 'a'){
        my $stmt = $self->dbh->prepare("INSERT INTO topics(title, date_created, creator_id) VALUES (?,?,?)")
                    or die $self->dbh->errstr;
        $status = $stmt->execute($title, $dateTime, $self->session->param('uid'));
        $self->dbh->commit();
    }
    if($status){
        $self->redirect('./index.pl?rm=home');   
    }else{
        die $status;
    }
}

#view topic
sub view_topic_rm{
    my $self = shift;
    
}

1;