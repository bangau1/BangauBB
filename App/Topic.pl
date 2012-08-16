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

sub getSortedThreadsByTopicId{
    my $self = shift;
    my $topicId = shift;
    my $from = shift;
    my $limit = shift;
    if(not defined $topicId){
        die "Topic ID parameter can't empty";
    }
    if(not defined $from){
        $from = 0;
    }
    if(not defined $limit){
        $limit = 10;
    }
    
    my $stmt = $self->dbh->prepare("
    SELECT
    td.id as thread_id, td.title as thread_title, u.username as thread_creator_username, td.date_created as thread_date_created,
    latest_post_id, latest_post_title, latest_post_creator_username,
    latest_post_date_created
    FROM threads td left outer join 
    (
        select p.thread_id as thread_id, p.id as latest_post_id, p.title as latest_post_title,
            p.date_created as latest_post_date_created, 
            u.username as latest_post_creator_username
        from posts p, users u
        where p.creator_id = u.id 
        order by latest_post_date_created DESC
        LIMIT 0, 1
    ) p
    ON p.thread_id = td.id 
    inner join users u
    where td.topic_id = $topicId and td.creator_id = u.id
    ORDER BY latest_post_date_created DESC
    LIMIT $from, $limit") or die $self->dbh->errstr;
    $stmt->execute();
    
    my @rows = ();
    push @rows, $_ while $_ = $stmt->fetchrow_hashref();
    return @rows;
}

#view topic
sub view_topic_rm{
    my $self = shift;
    my $tmpl = $self->load_tmpl('post/view_topic.tmpl',  die_on_bad_params => 0);
    my $topicId = $self->query->param('topic_id');
    
    if(not defined $topicId){
        $self->redirect("./index.pl?rm=home");
        return;
    }
    
    my $topicTitle = $self->dbh->selectrow_array("SELECT title FROM topics WHERE id = ?", {}, ($topicId));
    
    $self->passCredential_Session(\$tmpl);
    $tmpl->param('topic_id', $topicId);
    $tmpl->param(
        breadcrumbs => [
            { name => "Home", link=>"./index.pl?rm=home"},
            { name => $topicTitle, active => "true"},
        ]
    );
    my @rows = $self->getSortedThreadsByTopicId($topicId, 0, 10);
    $tmpl->param(threads => \@rows);
    return $tmpl->output();
}

#create thread
sub create_thread_rm{
    my $self = shift;
    my $topic_id = $self->query->param('t');
    my $tmpl = $self->load_tmpl('thread/create_thread.tmpl', die_on_bad_params => 0);
    $tmpl->param('topic_id', $topic_id);
    $self->passCredential_Session(\$tmpl);
    return $tmpl->output();
}

sub create_thread_post_rm{
    my $self= shift;
    my $q = $self->query();
    my ($title, $post, $topic_id ) = ($q->param('title'), $q->param('post'), $q->param('topic_id'));
    my $status = undef;
    #return "$title && $post && $topic_id && defined ".$self->session->param('uid');
    if($title && $post && $topic_id && defined $self->session->param('uid')){
        my $stmt = $self->dbh->prepare("INSERT INTO threads(title, post, date_created, date_modified, topic_id, creator_id) VALUES(?, ?, ?, ?, ?, ?)")
            or die $self->dbh->errstr;
        my $datetime = &toDateTime;
        #return "($title, $post, $datetime, $topic_id, $self->session->param('uid'))";
        $status = $stmt->execute($title, $post, $datetime, $datetime, $topic_id, $self->session->param('uid'));
        $self->dbh->commit();
    }
    
    my $thread_id = undef;
    if($status){
        $thread_id = $self->dbh->selectrow_array("SELECT LAST_INSERT_ID()") or die $self->dbh->errstr;
        $self->redirect("./index.pl?rm=view_thread&t=$thread_id");
    }else{
        die "fail";
    }
}

#view thread
sub view_thread_rm{
    my $self = shift;
    my $thread_id = $self->query->param('t');
    
    my $tmpl = $self->load_tmpl('thread/view_thread.tmpl', die_on_bad_params => 0);
    $self->passCredential_Session(\$tmpl);
    return $tmpl->output();
}
1;