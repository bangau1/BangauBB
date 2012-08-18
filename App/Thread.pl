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
        my $str = $ref->{'latest_post_date_created'};
        if($str){
            $str =~ /^(....)-(..)-(..) (..):(..):(..)$/;
            my $postDateCreated = DateTime->new(year => $1, month => $2, day=>$3, hour=>$4, minute=>$5, second => $6);
            my $dateNow = DateTime->now;
            my $durations = $dateNow-$postDateCreated;
            my @units = $durations->in_units( qw(minutes) );
            if($units[0] < 1440){ #within a day
                $ref->{'new_reply'} = 'true';
            }
        }
        
    }
    return @rows;
}
#create thread
sub create_thread_rm{
    my $self = shift;
    my $topic_id = $self->query->param('topic_id');
    
    my $tmpl = $self->load_tmpl('thread/create_thread.tmpl', die_on_bad_params => 0);
    $tmpl->param('topic_id', $topic_id);
    $self->passCredential_Session($tmpl);
    return $tmpl->output();
}
sub create_thread_confirm_rm{
    my $self = shift;
    my ($title, $ori_post, $topic_id, $image) = ($self->query->param('title'), $self->query->param('post'), $self->query->param('topic_id'), $self->query->param('image'));
    if($title and $ori_post and $topic_id and $self->session('user')){
        my $tmpl = $self->load_tmpl("thread/confirm.tmpl", die_on_bad_params=>0);
        if($image){
            my $image_id = md5_hex($self->session->param('uid').$title.$ori_post.$topic_id).md5_hex($image);
            $self->upload_image($image, $image_id);
            $tmpl->param(thread_image_url => $self->param('image_dir_url').$image_id);
            $tmpl->param(image_id => $image_id);
        }
        my $post = &filter_body_message($ori_post);
        $tmpl->param(thread_title => $title);
        $tmpl->param(thread_post => $post);
        $tmpl->param(thread_hidden_post => $ori_post);
        $tmpl->param(topic_id => $topic_id);
        $self->passCredential_Session($tmpl);
        return $tmpl->output();
    }elsif($topic_id){
        $self->redirect('./index.pl?rm=create_thread&topic_id='.$topic_id);
    }else{
        $self->redirect("./index.pl?rm=home");
    }
}

sub create_thread_post_rm{
    my $self= shift;
    my $q = $self->query();
    my ($title, $post, $topic_id, $image_id) = ($q->param('title'), $q->param('post'), $q->param('topic_id'), $q->param('image_id'));
    my $status = undef;
    #die "*-".$title."#".$post."#".$topic_id."#".$image_id."*";
    #return "$title && $post && $topic_id && defined ".$self->session->param('uid');
    if($title && $post && $topic_id && defined $self->session->param('uid')){
        my $sql = "";
        my $datetime = &toDateTime;
        my $stmt = undef;
        if($image_id){
            $sql = "INSERT INTO threads(title, post, date_created, date_modified, topic_id, creator_id, image_id) values(?,?,?,?,?,?,?)";
            $stmt = $self->dbh->prepare($sql)
            or die $self->dbh->errstr;
            $status = $stmt->execute($title, $post, $datetime, $datetime, $topic_id, $self->session->param('uid'), $image_id);
        }else{
            $sql = "INSERT INTO threads(title, post, date_created, date_modified, topic_id, creator_id) VALUES(?, ?, ?, ?, ?, ?)";
            $stmt = $self->dbh->prepare($sql)
            or die $self->dbh->errstr;
            $status = $stmt->execute($title, $post, $datetime, $datetime, $topic_id, $self->session->param('uid'));
        }
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
    SELECT td.id as thread_id, td.image_id as thread_image_id, td.date_created as thread_date_created, td.title as thread_title, td.post as thread_post, td.topic_id as topic_id,
    u.username as thread_creator_username, u.id as thread_creator_uid, LOWER(SUBSTRING(u.role, 1, 1)) as thread_creator_role, u.date_created as thread_creator_date_created
    FROM threads td, users u
    WHERE td.id = $thread_id and u.id = td.creator_id
    ") or die "Wrong SQL Statement: ".$self->dbh->errstr;
    $stmt->execute();
    
    #the thread is 1 only
    my @thread = ();
    if($_=$stmt->fetchrow_hashref()){
        my $ref = $_;
        #output the body
        $ref->{'thread_post'} = &filter_body_message($ref->{'thread_post'});
        
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
        if($ref->{'thread_image_id'}){
            $ref->{'thread_image_url'} = $self->param('image_dir_url').$ref->{'thread_image_id'};
        }
        if($ref->{'thread_creator_role'} eq 'a'){
            $ref->{'thread_creator_role'} = 'admin';
        }elsif($ref->{'thread_creator_role'} eq 'u'){
            $ref->{'thread_creator_role'} = 'user';
        }else{
            $ref->{'thread_creator_role'} = 'guest';
        }
        push @thread, $ref;
    }
    
    #ENDING fetching thread info
    
    #BEGINNING fetching reply from thread
    $stmt = $self->dbh->prepare("
    SELECT p.image_id as post_image_id, p.id as post_id, p.date_created as post_date_created, p.title as post_title, p.post as post_post,
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
        
        #output the body
        $ref->{'post_post'} = &filter_body_message($ref->{'post_post'});
        
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
        
        if($ref->{'post_image_id'}){
            $ref->{'post_image_url'} = $self->param('image_dir_url').$ref->{'post_image_id'};
        }
        if($ref->{'post_creator_role'} eq 'a'){
            $ref->{'post_creator_role'} = 'admin';
        }elsif($ref->{'post_creator_role'} eq 'u'){
            $ref->{'post_creator_role'} = 'user';
        }else{
            $ref->{'post_creator_role'} = 'guest';
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
sub delete_thread_post_rm{
    my $self = shift;
    my $thread_id = $self->query->param('t');
    my $topic_id = $self->query->param('topic_id');
    
    my ($uid, $role) = ($self->session->param('uid'), $self->session->param('role'));
    
    my @list_images_to_delete = ();
    #die $thread_id." ".$uid." ".$role;
    if($thread_id && $uid && $role){
        my $img_id = $self->dbh->selectrow_array("SELECT image_id FROM threads WHERE id = $thread_id");
        if($img_id){
            push @list_images_to_delete, $self->param('image_dir'). $img_id;
        }
        my @img_ids = $self->dbh->selectrow_array("SELECT image_id FROM posts WHERE thread_id = $thread_id");
        foreach $_(@img_ids){
            if($_){
                push @list_images_to_delete, $self->param('image_dir').$_;
            }
        }
        
        my $str = undef;
        
        if($role eq 'u'){
            $str = "DELETE FROM threads WHERE id = $thread_id AND creator_id = $uid";
        }elsif($role eq 'a'){
            $str = "DELETE FROM threads WHERE id = $thread_id";
        }else{
            $self->redirect("./index.pl?rm=view_topic&topic_id=$topic_id");
            return;
        }
        my $stmt = $self->dbh->prepare($str) or die;
        $stmt->execute();
        $self->dbh->commit();
        &delete_files(@list_images_to_delete);
        $self->redirect("./index.pl?rm=view_topic&topic_id=$topic_id");
        
    }else{
        $self->redirect("./index.pl?rm=view_topic&topic_id=$topic_id");
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
    SELECT td.image_id as thread_image_id, td.topic_id as topic_id, td.id as thread_id, td.date_created as thread_date_created, td.title as thread_title, td.post as thread_post,
    u.username as thread_creator_username, u.id as thread_creator_uid, LOWER(SUBSTRING(u.role, 1, 1)) as thread_creator_role, u.date_created as thread_creator_date_created
    FROM threads td, users u
    WHERE td.id = $thread_id and u.id = td.creator_id
    ") or die "Wrong SQL Statement: ".$self->dbh->errstr;
    $stmt->execute();
    
    #the thread is 1 only
    my @thread = ();
    if($_=$stmt->fetchrow_hashref()){
        my $ref = $_;
        $ref->{'thread_post'} = &filter_body_message($ref->{'thread_post'});
        
        if($ref->{'thread_image_id'}){
            $ref->{'thread_image_url'} = $self->param('image_dir_url').$ref->{'thread_image_id'};
        }
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
            return;
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
1;