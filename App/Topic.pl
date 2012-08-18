#service
use strict;
use Digest::SHA qw(sha1 sha1_hex sha1_base64);
use DBI;
use POSIX qw(ceil);
use List::Util qw(min max);

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
        select td.topic_id as topic_id, td.id as thread_id, td.title as thread_title,
        u.username as username, pp.date_created as date_modified
        from threads td, users u, posts pp
        where  pp.thread_id = td.id AND pp.creator_id = u.id 
        order by date_modified DESC
        LIMIT 0, 1
    ) p
    ON p.topic_id = t.id
    ORDER BY date_modified DESC
    LIMIT $from, $limit
    ") or die $self->dbh->errstr;
    $stmt->execute();
    
    my @rows = ();
    push @rows, $_ while $_ = $stmt->fetchrow_hashref();
    foreach my $ref(@rows){
        my $total_thread = $self->dbh->selectrow_array("SELECT COUNT(*) as total_thread FROM threads td
                                    WHERE td.topic_id = ".$ref->{'topic_id'});
        my $total_post = $self->dbh->selectrow_array("SELECT COUNT(*) as total_post FROM posts p, threads td
                                    WHERE td.topic_id = ".$ref->{'topic_id'}." and td.id = p.thread_id");
        $ref->{'total_thread'} = $total_thread;
        $ref->{'total_post'} = $total_post;
    }
    return @rows;
}
#home_page
sub home_rm{
    my $self = shift;
    my $page = $self->query->param('page');
    if(not defined $page){
        $page = 1;
    }
    $page -= 1; #start with zero based page
    
    my $tmpl = $self->load_tmpl('membership/home.tmpl',  die_on_bad_params => 0);
    
    $self->passCredential_Session($tmpl);
    
    $tmpl->param(
        breadcrumbs => [
            { name => "Home", link=>"./index.pl?rm=home", active=>"true"},
        ]
    );
    
    #BEGIN PAGINATION HANDLING
    my $total_topic = $self->dbh->selectrow_array("SELECT COUNT(*) FROM topics");
    my $limit = $self->param('topics_per_page');
    my $total_pages = max(ceil($total_topic/$limit), 1);
    my $limit_pagination = $self->param('page_per_pagination');
    
    
    if(($page+1) > $total_pages){
        die "error params";
    }
    my $start_page = ceil(($page+1)/$limit_pagination);
    my $end_page = min($start_page + $limit_pagination - 1, $total_pages);
    
    
    my @pages = ();
    foreach my $ind(($start_page-1)..($end_page+1)){
        my %hash = {};
        if($ind == ($start_page-1)){
            if($ind <= 0){
                $hash{'disabled'} = "true";                
                
            }else{
                $hash{'not_both'} = "true";
                $hash{'link'} = "./index.pl?rm=home&page=".$ind;   
            }
            $hash{'page'} = "«";
            
        }elsif($ind == ($end_page+1)){
            if($ind > $total_pages){
                $hash{'disabled'} = "true";
            }else{
                $hash{'not_both'} = "true";                
                $hash{'link'} = "./index.pl?rm=home&page=".$ind;
            }
            $hash{'page'} = "»";
        }else{
            if($ind == ($page+1)){
                $hash{'active'} = "true";
            }else{
                $hash{'not_both'} = "true";
            }
            $hash{'link'} = "./index.pl?rm=home&page=".$ind;
            $hash{'page'} = $ind;
        }
        push @pages, \%hash;
    }
    
    #END PAGINATION HANDLING
    
    my @rows = $self->getSortedTopicsForHomePage($page*$limit, ($page+1)*$limit);
    $tmpl->param(topics => \@rows);
    $tmpl->param(pages => \@pages);
    
    return $tmpl->output();
}

#create topic
sub create_topic_rm{
    my $self = shift;
    my $tmpl = $self->load_tmpl('post/create_topic.tmpl', die_on_bad_params => 0);
    if($self->session->param('role') eq 'a'){
        $self->passCredential_Session($tmpl);
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
        my $topicId = $self->dbh->last_insert_id(undef, undef, 'topics', 'id');
        $self->redirect("./index.pl?rm=view_topic&topic_id=$topicId");
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
    foreach my $ref(@rows){
        my $total_reply = $self->dbh->selectrow_array("SELECT COUNT(*) FROM posts p WHERE p.thread_id = ".$ref->{'thread_id'});
        $ref->{'total_reply'} = $total_reply;
    }
    return @rows;
}

#view topic
sub view_topic_rm{
    my $self = shift;
    my $tmpl = $self->load_tmpl('post/view_topic.tmpl',  die_on_bad_params => 0);
    my $topicId = $self->query->param('topic_id');
    my $page = $self->query->param('page');
    if(not defined $page){
        $page = 1;
    }
    
    $page -=1;
    
    if(not defined $topicId){
        $self->redirect("./index.pl?rm=home");
        return;
    }
    
    my $topicTitle = $self->dbh->selectrow_array("SELECT title FROM topics WHERE id = ?", {}, ($topicId));
    
    #BEGIN PAGINATION HANDLING
    my $total_thread = $self->dbh->selectrow_array("SELECT COUNT(*) FROM threads WHERE topic_id = $topicId");
    my $limit = $self->param('threads_per_page');
    my $total_pages = max(ceil($total_thread/$limit), 1); #case for 0 thread, then just 1 pagination
    my $limit_pagination = $self->param('page_per_pagination');
    
    
    if(($page+1) > $total_pages){
        die "error params";
    }
    my $start_page = ceil(($page+1)/$limit_pagination);
    my $end_page = min($start_page + $limit_pagination - 1, $total_pages);
    
    
    my @pages = ();
    foreach my $ind(($start_page-1)..($end_page+1)){
        my %hash = {};
        if($ind == ($start_page-1)){
            if($ind <= 0){
                $hash{'disabled'} = "true";                
                
            }else{
                $hash{'not_both'} = "true";
                $hash{'link'} = "./index.pl?rm=view_topic&topic_id=$topicId&page=".$ind;
            }
            $hash{'page'} = "«";
            
        }elsif($ind == ($end_page+1)){
            if($ind > $total_pages){
                $hash{'disabled'} = "true";
            }else{
                $hash{'not_both'} = "true";                
                $hash{'link'} = "./index.pl?rm=view_topic&topic_id=$topicId&page=".$ind;
            }
            $hash{'page'} = "»";
        }else{
            if($ind == ($page+1)){
                $hash{'active'} = "true";
            }else{
                $hash{'not_both'} = "true";
            }
            $hash{'link'} = "./index.pl?rm=view_topic&topic_id=$topicId&page=".$ind;
            $hash{'page'} = $ind;
        }
        push @pages, \%hash;
    }
    
    #END PAGINATION HANDLING
    
    $self->passCredential_Session($tmpl);
    $tmpl->param('topic_id', $topicId);
    $tmpl->param(pages => \@pages);
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
    $self->passCredential_Session($tmpl);
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
    my $q = $self->query();
    
    if($q->param('single_post')){
        die "not supported";   
    }
    my $role = 'g';
    my $userid = undef;
    if($self->session->param('role')){
        $role = $self->session->param('role');
    }
    if($self->session->param('uid')){
        $userid = $self->session->param('uid');
    }
    
    #BEGINNING fetch thread info
    my $stmt = $self->dbh->prepare("
    SELECT td.id as thread_id, td.date_created as thread_date_created, td.title as thread_title, td.post as thread_post, td.topic_id as topic_id,
    u.username as thread_creator_username, u.id as thread_creator_uid, LOWER(SUBSTRING(u.role, 1, 1)) as thread_creator_role, u.date_created as thread_creator_date_created
    FROM threads td, users u
    WHERE td.id = $thread_id and u.id = td.creator_id
    ") or die "Wrong SQL Statement: ".$self->dbh->errstr;
    $stmt->execute();
    
    #the thread is 1 only
    my @thread = ();
    if($_=$stmt->fetchrow_hashref()){
        my $ref = $_;
        my ($post_count, $thread_count) = (0,0);
        $post_count = $self->dbh->selectrow_array("SELECT COUNT(*) FROM posts p
                                                  WHERE p.creator_id = ".${$_}{'thread_creator_uid'});
        $thread_count = $self->dbh->selectrow_array("SELECT COUNT(*) FROM threads td
                                                    WHERE td.creator_id = ".${$_}{'thread_creator_uid'});
        $ref->{'thread_creator_total_post'} = $post_count;
        $ref->{'thread_creator_total_thread'} = $thread_count;
        if(($userid && $ref->{'thread_creator_uid'} eq $userid) || $role eq 'a'){
            $ref->{'can_delete'} = 'true';   
        }
        push @thread, $ref;
    }
    
    #ENDING fetching thread info
    
    #BEGINNING fetching reply from thread
    $stmt = $self->dbh->prepare("
    SELECT p.id as post_id, p.date_created as post_date_created, p.title as post_title, p.post as post_post,
    u.username as post_creator_username, u.id as post_creator_uid, p.thread_id as thread_id, u.date_created as post_creator_date_created,
    LOWER(SUBSTRING(u.role, 1, 1)) as post_creator_role
    FROM posts p, users u
    WHERE p.thread_id = $thread_id and p.creator_id = u.id
    ORDER BY post_date_created DESC
    ") or die "WRONG SQL STATEMENT:".$self->dbh->errstr;
    
    $stmt->execute();
    my @replies = ();
    push @replies, $_ while $_=$stmt->fetchrow_hashref();
    
    
    foreach my $ref(@replies){
        my ($post_count, $thread_count) = (0,0);
        $post_count = $self->dbh->selectrow_array("SELECT COUNT(*) FROM posts p
                                                  WHERE p.creator_id = ".$ref->{'post_creator_uid'});
        $thread_count = $self->dbh->selectrow_array("SELECT COUNT(*) FROM threads td
                                                    WHERE td.creator_id = ".$ref->{'post_creator_uid'});
        ${$ref}{'post_creator_total_post'} = $post_count;
        ${$ref}{'post_creator_total_thread'} = $thread_count;
        if(($userid && $ref->{'post_creator_uid'} eq $userid) || $role eq 'a'){
            $ref->{'can_delete'} = 'true';   
        }
    }
    #ENDING
    #GET TOPIC TITLE for breadcrumbs info. @threads contains maximal 1 item
    my $topic_title = $self->dbh->selectrow_array("SELECT title FROM topics WHERE id = ".$thread[0]->{'topic_id'});
    
    my $tmpl = $self->load_tmpl('thread/view_thread.tmpl', die_on_bad_params => 0);
    #passing parameter
    $tmpl->param(
        breadcrumbs=>[
            {name => "Home", link => "./index.pl?rm=home"},
            {name => $topic_title, link => "./index.pl?rm=view_topic&topic_id=".$thread[0]->{'topic_id'}},
            {name => $thread[0]->{'thread_title'}, active=>"true"}
        ]
    );
    $self->passCredential_Session($tmpl);
    $tmpl->param(threads => \@thread);
    $tmpl->param(posts => \@replies);
    return $tmpl->output();
}

#reply
sub create_reply_rm{
    my $self = shift;
    my $thread_id = $self->query->param('t');
    if(not defined $thread_id){
        $self->redirect('./index.pl?rm=home');
        return;
    }
    my $tmpl = $self->load_tmpl('post/create_reply.tmpl', die_on_bad_params => 0);
    $tmpl->param('thread_id', $thread_id);
    $self->passCredential_Session($tmpl);
    return $tmpl->output();
    
}
sub create_reply_post_rm{
    my $self= shift;
    my $q = $self->query();
    my ($title, $post, $thread_id ) = ($q->param('title'), $q->param('post'), $q->param('thread_id'));
    my $status = undef;
    
    my ($userid, $role) = ($self->session->param('uid'), $self->session->param('role'));
    if(not defined $userid){
        $userid = $self->param('guest_id');
        $role = 'g';
    }
    if($post && $thread_id){
        if($title){
            my $stmt = $self->dbh->prepare("INSERT INTO posts(title, post, date_created, thread_id, creator_id) VALUES(?, ?, ?, ?, ?)")
                or die $self->dbh->errstr;
            my $datetime = &toDateTime;
            $status = $stmt->execute($title, $post, $datetime, $thread_id, $userid);   
        }else{
            my $stmt = $self->dbh->prepare("INSERT INTO posts(post, date_created, thread_id, creator_id) VALUES( ?, ?, ?, ?)")
                or die $self->dbh->errstr;
            my $datetime = &toDateTime;
            $status = $stmt->execute($post, $datetime, $thread_id, $userid); 
        }
        $self->dbh->commit();
    }else{
        die "must provide post and thread_id";
    }
    
    my $post_id = undef;
    if($status){
        $post_id = $self->dbh->selectrow_array("SELECT LAST_INSERT_ID()") or die $self->dbh->errstr;
        $self->redirect("./index.pl?rm=view_thread&t=$thread_id#div-post-$post_id");
    }else{
        die "fail";
    }
}

sub delete_reply_rm{
    my $self = shift;
    my $post_id = $self->query->param('p');
    my $q = $self->query();
    
    my $role = 'g';
    my $userid = undef;
    if($self->session->param('role')){
        $role = $self->session->param('role');
    }
    if($self->session->param('uid')){
        $userid = $self->session->param('uid');
    }
    
    
    #BEGINNING fetching reply info
    my $stmt = $self->dbh->prepare("
    SELECT p.id as post_id, p.date_created as post_date_created, p.title as post_title, p.post as post_post,
    u.username as post_creator_username, u.id as post_creator_uid, p.thread_id as thread_id, u.date_created as post_creator_date_created,
    LOWER(SUBSTRING(u.role, 1, 1)) as post_creator_role
    FROM posts p, users u
    WHERE p.id = $post_id and p.creator_id = u.id
    ") or die "WRONG SQL STATEMENT:".$self->dbh->errstr;
    
    $stmt->execute();
    my @replies = ();
    push @replies, $_ while $_=$stmt->fetchrow_hashref();
    
    # just 1 only
    foreach my $ref(@replies){
        my ($post_count, $thread_count) = (0,0);
        $post_count = $self->dbh->selectrow_array("SELECT COUNT(*) FROM posts p
                                                  WHERE p.creator_id = ".$ref->{'post_creator_uid'});
        $thread_count = $self->dbh->selectrow_array("SELECT COUNT(*) FROM threads td
                                                    WHERE td.creator_id = ".$ref->{'post_creator_uid'});
        ${$ref}{'post_creator_total_post'} = $post_count;
        ${$ref}{'post_creator_total_thread'} = $thread_count;
        if(($userid && $ref->{'post_creator_uid'} eq $userid) || $role eq 'a'){
            $ref->{'can_delete'} = 'true';   
        }else{
            $self->redirect('./index.pl?rm=home');
            return;
        }
    }
    #ENDING
    
    my $tmpl = $self->load_tmpl('post/delete_reply.tmpl', die_on_bad_params => 0);
    #passing parameter
    $self->passCredential_Session($tmpl);
    $tmpl->param(posts => \@replies);
    return $tmpl->output();
}

sub delete_reply_post_rm{
    my $self = shift;
    my $post_id = $self->query->param('p');
    my $thread_id = $self->query->param('t');
    
    my ($uid, $role) = ($self->session->param('uid'), $self->session->param('role'));
    if($post_id && $uid && $role){
        my $str = undef;
        if($role eq 'u'){
            $str = "DELETE FROM posts WHERE id = $post_id AND creator_id = $uid";
        }elsif($role eq 'a'){
            $str = "DELETE FROM posts WHERE id = $post_id";
        }else{
            $self->redirect("./index.pl?rm=view_thread&t=$thread_id");
            return;
        }
        my $stmt = $self->dbh->prepare($str) or die;
        $stmt->execute();
        $self->dbh->commit();
        $self->redirect("./index.pl?rm=view_thread&t=$thread_id");
        
    }else{
        $self->redirect("./index.pl?rm=view_thread&t=$thread_id");
    }
}

sub delete_thread_rm{
    my $self = shift;
    my $thread_id = $self->query->param('t');
    my $q = $self->query();
    
    my $role = 'g';
    my $userid = undef;
    if($self->session->param('role')){
        $role = $self->session->param('role');
    }
    if($self->session->param('uid')){
        $userid = $self->session->param('uid');
    }
    
    #BEGINNING fetch thread info
    my $stmt = $self->dbh->prepare("
    SELECT td.topic_id as topic_id, td.id as thread_id, td.date_created as thread_date_created, td.title as thread_title, td.post as thread_post,
    u.username as thread_creator_username, u.id as thread_creator_uid, LOWER(SUBSTRING(u.role, 1, 1)) as thread_creator_role, u.date_created as thread_creator_date_created
    FROM threads td, users u
    WHERE td.id = $thread_id and u.id = td.creator_id
    ") or die "Wrong SQL Statement: ".$self->dbh->errstr;
    $stmt->execute();
    
    #the thread is 1 only
    my @thread = ();
    if($_=$stmt->fetchrow_hashref()){
        my $ref = $_;
        my ($post_count, $thread_count) = (0,0);
        $post_count = $self->dbh->selectrow_array("SELECT COUNT(*) FROM posts p
                                                  WHERE p.creator_id = ".${$_}{'thread_creator_uid'});
        $thread_count = $self->dbh->selectrow_array("SELECT COUNT(*) FROM threads td
                                                    WHERE td.creator_id = ".${$_}{'thread_creator_uid'});
        $ref->{'thread_creator_total_post'} = $post_count;
        $ref->{'thread_creator_total_thread'} = $thread_count;
        if(($userid && $ref->{'thread_creator_uid'} eq $userid) || $role eq 'a'){
            $ref->{'can_delete'} = 'true';   
        }else{
            $self->redirect(".index.pl?rm=view_thread&t=$thread_id");
        }
        push @thread, $ref;
    }
    
    #ENDING fetching thread info
    
    
    my $tmpl = $self->load_tmpl('thread/delete_thread.tmpl', die_on_bad_params => 0);
    #passing parameter
    $self->passCredential_Session($tmpl);
    $tmpl->param(threads => \@thread);
    return $tmpl->output();
}
sub delete_thread_post_rm{
    my $self = shift;
    my $thread_id = $self->query->param('t');
    my $topic_id = $self->query->param('topic_id');
    
    my ($uid, $role) = ($self->session->param('uid'), $self->session->param('role'));
    if($thread_id && $uid && $role){
        my $str = undef;
        if($role eq 'u'){
            $str = "DELETE FROM posts WHERE id = $thread_id AND creator_id = $uid";
        }elsif($role eq 'a'){
            $str = "DELETE FROM posts WHERE id = $thread_id";
        }else{
            $self->redirect("./index.pl?rm=view_topic&topic_id=$topic_id");
            return;
        }
        my $stmt = $self->dbh->prepare($str) or die;
        $stmt->execute();
        $self->dbh->commit();
        $self->redirect("./index.pl?rm=view_topic&topic_id=$topic_id");
        
    }else{
        $self->redirect("./index.pl?rm=view_topic&topic_id=$topic_id");
    }
}
1;
