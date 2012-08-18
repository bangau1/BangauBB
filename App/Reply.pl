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
    my ($title, $post, $thread_id, $image_id) = ($q->param('title'), $q->param('post'), $q->param('thread_id'), $q->param('image_id'));
    my $status = undef;
    
    my ($userid, $role) = ($self->session->param('uid'), $self->session->param('role'));
    if(not defined $userid){
        $userid = $self->param('guest_id');
        $role = 'g';
    }
    if($post && $thread_id){
        if($title){
            my $stmt = $self->dbh->prepare("INSERT INTO posts(title, post, date_created, thread_id, creator_id, image_id) VALUES(?, ?, ?, ?, ?, ?)")
                or die $self->dbh->errstr;
            my $datetime = &toDateTime;
            $status = $stmt->execute($title, $post, $datetime, $thread_id, $userid, $image_id);   
        }else{
            my $stmt = $self->dbh->prepare("INSERT INTO posts(post, date_created, thread_id, creator_id, image_id) VALUES( ?, ?, ?, ?, ?)")
                or die $self->dbh->errstr;
            my $datetime = &toDateTime;
            $status = $stmt->execute($post, $datetime, $thread_id, $userid, $image_id); 
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
    SELECT p.image_id as post_image_id, p.id as post_id, p.date_created as post_date_created, p.title as post_title, p.post as post_post,
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
        $ref->{'post_post'} = &filter_body_message($ref->{'post_post'});
        
        if($ref->{'post_image_id'}){
            $ref->{'post_image_url'} = $self->param('image_dir_url').$ref->{'post_image_id'};
        }
        
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
    my @list_images_to_delete = ();
    
    if($post_id && $uid && $role){
        my $img_id = $self->dbh->selectrow_array("SELECT image_id FROM posts WHERE id = $post_id");
        if($img_id){
            push @list_images_to_delete, $self->param('image_dir'). $img_id;
        }
        
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
        &delete_files(@list_images_to_delete);
        $self->redirect("./index.pl?rm=view_thread&t=$thread_id");
        
    }else{
        $self->redirect("./index.pl?rm=view_thread&t=$thread_id");
    }
}

sub create_reply_confirm_rm{
    my $self = shift;
    my ($title, $ori_post, $thread_id, $image) = ($self->query->param('title'), $self->query->param('post'), $self->query->param('thread_id'), $self->query->param('image'));
    if($ori_post and $thread_id){
        my $tmpl = $self->load_tmpl("post/create_reply_confirm.tmpl", die_on_bad_params=>0);
        if($image){
            my $image_id = md5_hex($self->session->param('uid').$title.$ori_post.$thread_id).md5_hex($image);
            $self->upload_image($image, $image_id);
            $tmpl->param(post_image_url => $self->param('image_dir_url').$image_id);
            $tmpl->param(image_id => $image_id);
        }
        my $post = &filter_body_message($ori_post);
        $tmpl->param(post_title => $title);
        $tmpl->param(post_post => $post);
        $tmpl->param(post_hidden_post => $ori_post);
        $tmpl->param(thread_id => $thread_id);
        $self->passCredential_Session($tmpl);
        return $tmpl->output();
    }elsif($thread_id){
        $self->redirect('./index.pl?rm=view_thread&t='.$thread_id);
    }else{
        $self->redirect('./index.pl?rm=view_thread&t='.$thread_id);
    }
}

1;