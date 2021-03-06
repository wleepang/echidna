class MainController < ApplicationController
  
  include Util
  include DataOutputHelper
  
  filter_parameter_logging :password
  protect_from_forgery :only => [:create, :update, :destroy] 
  before_filter :authorize, :except => [:get_logged_in_user, :login, :request_password_refresh, :register] 
  
#  def log_actions(controller)
#    puts "hello from big brother, #{controller.action_name}, id = #{session}"
#  end



  before_filter do |controller|
    unless (controller.session[:user].nil?)
      user = User.find_by_email controller.get_email_from_session_user
      unless user.nil?
        la = LoggedAction.new(:user_id => user.id, :action => controller.action_name)
        la.save
     end
    end
  end
  
  
  def index
    url = request.url
    if RAILS_ENV == 'production'
      redirect_to "#{url}/"
    else
      render :text => "not implemented in development mode"
    end
    
    #render :text => request.url
    #render :text => "#{url}/index.html"
  end

  def test
    render :text => "ok"
  end
  
  def authorize
    render :text => "not logged in" and return false unless session[:user]
  end
  
  
  
  def get_logged_in_user
    
    diaghash = {}
    diaghash[:su] = session[:user]
    diaghash[:cookies] = cookies
    diaghash[:email] = ""
    diaghash[:rtv] = false
    diaghash[:rescue] = false
    diaghash[:cookies_empty_or_nil] = false
    diaghash[:returning] = ""
    diaghash[:remote_ip] = request.remote_ip
    diaghash[:user_agent] = request.env["HTTP_USER_AGENT"]
    email = ''
    
    
    if (session[:user])
      cookies['echidna_cookie'] = {:value => create_cookie(session[:user]), :expires => 1000.days.from_now}
    else
      for cookie in cookies
        if cookie.first =~ /echidna_cookie/
          unless session[:user]
            puts "wadata"
            email = cookie.last.to_s.gsub(/echidna_cookie=/,"").gsub("%40","@") #if cookie.last.respond_to?(:gsub)
            puts "email = #{email}"
            session[:user] = email
            diaghash[:email] = email
          end
          puts "hack setting cookie"
          if (session[:user]).respond_to?(:value)
            diaghash[:rtv] = true
            session[:user] = session[:user].value
          else
            email = session[:user]
          end
          puts "e = #{email}"

          cookies['echidna_cookie'] = {:value => create_cookie(email), :expires => 1000.days.from_now}
        end
      end
    end
    
    


    if session[:user].nil?
      begin
        if (valid_cookie?(cookies['echidna_cookie']['value']))
          session[:user] = cookies['echidna_cookie']['value'].split(";").first
        else
          render :text => "not logged in" and return false
        end
      rescue Exception => ex
        diaghash[:rescue] = true
        logger.info ex.message
        logger.info ex.backtrace
        diaghash[:status] = "problem setting session user"
        logger.info "problem setting session user"
        diag_email(diaghash)
        render :text => "not logged in" and return false
      end
    else
      cookies['echidna_cookie'] = {:value => create_cookie(session[:user]), :expires => 1000.days.from_now}
    end

    
    if cookies['echidna_cookie'].nil? or cookies['echidna_cookie'].empty?
      logger.info "cookie is nil or empty"
      diaghash[:cookies_empty_or_nil] = true
      diag_email(diaghash)
      
      render :text => 'not logged in' and return false
    end
    
    
    
    logger.info "returning #{session[:user]}"
    diaghash[:returning] = session[:user]
    diag_email(diaghash)
    render :text => get_email_from_session_user
  end
  
  
  def get_email_from_session_user()
    tmp = session[:user].split("%").first
    tmp.split(";").first
  end
  
  def diag_email(diaghash)
    s = diaghash.values.join(" ") + diaghash.keys.join(" ")
    #if (RAILS_ENV == 'production' and s !~ /dtenenbau/)
    if (RAILS_ENV == 'production')
      diaghash[:keylist] = diaghash.keys.map{|i|i.to_s}.sort
      # disable this for now
      #logger.info "sending diagnostic email - #{s}"
      #UserMailer.deliver_diag(diaghash)
    end
  end
  

  # todo make more secure
  
  
  def do_login(user)
    return "not logged in" unless user
    puts "in do_login, user.email is #{user.email}"
    user.last_login_date = Time.now
    user.save
    cookies['echidna_cookie'] = {:value => create_cookie(user[:email]),
      :expires => 1000.days.from_now }
    session[:user] = user.email
    session[:user_id] = user.id
    user.email
  end
  
  def login
    if (params[:token] and params[:reset_password]) #user is changing password
      user = User.find_by_email(params[:email])
      #user = User.find_by_sql(["select * from users where email = ?", params[:email]]).first
      if (Password::check("#{params[:email]}~~~#{SECRET_SALT}",params[:token]))
        user.password = params[:password]
        user.save
        
        render :text => do_login(user) and return false
      else
        user = nil
      end
    elsif params[:token] # user is validating account
      user = User.authenticate(params[:email], params[:password], false)
      render :text => "not logged in" and return false unless user
      if (Password::check("#{params[:email]}~~~#{SECRET_SALT}",params[:token]))
        user.validated = true
        user.save
        render :text => do_login(user) and return false
      else
        render :text => "not logged in" and return false
      end
    else # it's just a regular login
      user = User.authenticate(params[:email], params[:password]) 
    end



    render :text => do_login(user)
    
  end
  
  
  
  def logout
    cookies.delete(:echidna_cookie)
    session[:user] = nil  
    session[:user_id] = nil
    render :text => 'logged out'
  end
  
  
  
  def has_been_imported_already
    existing = Condition.find_by_sql(["select * from conditions where sbeams_project_id = ? and sbeams_timestamp = ?",
      params[:projectId].to_i, params[:dateDir]])
    render :text => (existing.empty?) ? "false" : "true"
  end
  
  
  def get_filtered_conditions
    if params[:result_type] == 'all'
      conds = Condition.find :all, :order => 'id'
    elsif params['result_type'] == 'ungrouped'
      conds = Condition.find_by_sql "select * from conditions where id not in (select distinct condition_id from condition_groupings)"
    elsif params['result_type'] == 'grouped'
      conds = Condition.find_by_sql "select * from conditions where id in (select distinct condition_id from condition_groupings)"
    #elsif params['result_type'] == 'sharedbyothers'
    end

    sorted_conds = sort_conditions_for_time_series(conds)
    headers['Content-type'] = 'text/plain'
    
    sorted_conds = Condition.populate_num_groups(sorted_conds)
    render :text => sorted_conds.to_json(:methods => :num_groups) 
    #render :text => sorted_conds.to_json() 


  end
  
  def remove_conditions_from_group
    ids_to_remove = ActiveSupport::JSON.decode(params[:ids_to_remove])
    records_to_remove = ConditionGrouping.find_by_sql([\
      "select id from condition_groupings where condition_group_id = ? and condition_id in (?)",
      params[:group_id],ids_to_remove]).map{|i|i.id}
    ConditionGrouping.delete(records_to_remove)
    render :text => "ok"
  end
 
  def get_groups_by_tags
    cond_ids = []
    tags = params[:tags].split(",")
    
    tags.each do |i|
      res = Condition.find_by_sql(["select distinct condition_id from tags where tag = ?", i])
      cond_ids += res.map{|item|item.condition_id.to_i}
    end
    
    
    results = Condition.find_by_sql(["select * from conditions where id in (?)",cond_ids.uniq])
    
    groups = get_groups_for_conditions(results)
    if (groups.empty?)
      render :text => "none" and return false
    else
      ret = []
      groups.each do |g|
        h = g.attributes
        h['num_results'] = g.num_results
        ret << {"condition_group" => h}
      end
      render :text => ret.to_json
    end
    
  end
 
  # todo rename
  def search_conditions
    search = ActiveSupport::JSON.decode(params[:search])
    wildcards = []
    for item in search
      if item =~ /\*/
        wildcards << item.gsub("*","%")
        search.delete item
      end
    end
    ids = Condition.find_by_sql(["select distinct condition_id from search_terms where word in (?)", search]).map{|i|i.condition_id}
    for wildcard in wildcards
      ids += Condition.find_by_sql(["select distinct condition_id from search_terms where word like ?", wildcard]).map{|i|i.condition_id}
    end
    
    
    results = Condition.find_by_sql(["select * from conditions where id in (?)",ids])
    
    groups = get_groups_for_conditions(results)
    if (groups.empty?)
      render :text => "none" and return false
    else
      ret = []
      groups.each do |g|
        h = g.attributes
        h['num_results'] = g.num_results
        ret << {"condition_group" => h}
      end
      render :text => ret.to_json
    end
    
  end
  
  def get_all_conditions
     conds = Condition.find :all, :order => 'id'
    sorted_conds = sort_conditions_for_time_series(conds)
    headers['Content-type'] = 'text/plain'
    sql = "select "
    sorted_conds = Condition.populate_num_groups(sorted_conds)
    render :text => sorted_conds.to_json(:methods => :num_groups) 
  end
  
  def check_if_group_exists
    group = ConditionGroup.find_by_name params[:group_name]
    render :text => (not group.nil?)
  end
  
  def create_new_group
    ids = ActiveSupport::JSON.decode params[:ids]
    group = ConditionGroup.new(:name => params[:name])
    begin
      ConditionGroup.transaction do
        group.save
        ids.each_with_index {|i,index|ConditionGrouping.new(:condition_id => i, :condition_group_id => group.id, :sequence => index +1).save}
        render :text => group.id
      end
    rescue Exception => ex
      puts ex.message
      puts ex.backtrace
    end
  end
  
  def get_all_groups
    groups = ConditionGroup.find :all, :order => 'name'
    ret = []
    groups.each do |g|
      h = g.attributes
      h['num_results'] = g.num_results
      ret << {"condition_group" => h}
    end
    render :text => ret.to_json # todo find out how to run the AR::B version of to_json
  end
  
  def get_conditions_for_group
    conds = find_conditions_for_group(params[:group_id])
      render :text => conds.to_json
  end

  def get_conditions_for_groups()
    conds = Condition.find_by_sql(["select c.name, g.condition_group_id, g.condition_id from conditions c, condition_groupings g where g.condition_id = c.id and g.condition_group_id in (?) order by g.condition_group_id, c.sequence", params[:group_ids].split(",")])
    render :text => conds.to_json
  end
  
  
  def reorder_group
    conds = Condition.find_by_sql(\
      ["select * from conditions where id in (select condition_id from condition_groupings where condition_group_id = ? order by sequence)",
      params[:group_id]])
    sequence = ActiveSupport::JSON.decode(params[:ids])
    begin
      ConditionGrouping.transaction do
        sequence.each_with_index do |s,index|
          #logger.debug "s = #{s}"
          item = ConditionGrouping.find_by_condition_id_and_condition_group_id(s,params[:group_id])
          #logger.info "old sequence: #{item.sequence} new sequence: #{index+1}"
          item.sequence = (index+1)
          item.save
          #logger.info "after save, sequence: #{item.sequence}"
        end
      end
    rescue Exception => ex
      puts ex.message
      puts ex.backtrace
    end
    render :text => "ok"#{}"#{params[:group_id]} :: #{params[:ids]} old order: #{conds.map{|i|i.id}.join(",")}"
    
  end

  def add_conditions_to_existing_group
    ids = ActiveSupport::JSON.decode(params[:ids])
    existing = ConditionGrouping.find_by_sql(["select * from condition_groupings where condition_id in (?) and condition_group_id = ?",
      ids,params['group_id'].to_i])
    max_seq = ConditionGrouping.find_by_sql(["select count(id) as result from condition_groupings where condition_group_id = ?",params[:group_id].to_i]).first().result().to_i
    max_seq += 1
      
    result = 'ok'
    result = 'warning' unless existing.empty?
    begin
      ConditionGrouping.transaction do
        ids.each do |id|
          already = existing.find{|i|i.condition_id == id}
          next unless already.nil?
          cg = ConditionGrouping.new(:sequence => max_seq, :condition_group_id => params[:group_id], :condition_id => id)
          cg.save
          max_seq += 1
        end
      end
    rescue Exception => ex
      puts ex.message
      puts ex.backtrace
    end
    render :text => result
  end

  def get_groups_for_condition
    groups = \
      ConditionGroup.find_by_sql(\
      ["select * from condition_groups where id in (select distinct condition_group_id from condition_groupings where condition_id = ?) order by name",
      params[:condition_id]])
    render :text => groups.to_json
  end
  
  def get_condition_detail # seems like species should be an observation, not a column in conditions
    cond = Condition.find(params[:condition_id])
    result = {}
    if (cond.name_parseable?)
      result = cond.parse_name
    else
      result = cond.get_obs();
    end
    result['Species'] = cond.species.name
    render :text => result.to_json
    
    
  end
  
  def get_relationship_types
    render :text => RelationshipType.find(:all, :order => 'name').to_json
  end
  
  def get_data #todo - make it work for location-based data as well
    
    cond_ids = Condition.find_by_sql(["select condition_id from condition_groupings where condition_group_id = ? order by sequence",
      params[:group_id]]).map{|i|i.condition_id}
  
    data = get_matrix_data(cond_ids,params[:data_type])

    #    respond_to do |format|
    #      format.xml {render :text => DataOutputHelper.as_matrix(data)}
    #      format.text {render :text => DataOutputHelper.as_matrix(data)}
    #    end
    headers['Content-type'] = 'text/plain'
    render :text => as_json(data)
  
  
  end
  
  def get_data_for_conditions
    cond_ids = params[:condition_ids].split(",")
    data = get_matrix_data(cond_ids,params[:data_type])

    headers['Content-type'] = 'text/plain'
    render :text => as_json(data)
    
  end
  
  
  def get_data_for_groups
    puts "in get_data_for_groups action at #{Time.now}"
    group_ids = params[:group_ids].split(",")
    cond_ids = []
    for group_id in group_ids
      cond_ids += ConditionGrouping.find_by_sql(["select condition_id from condition_groupings where condition_group_id = ? order by sequence",group_id])
    end
    # silently removes redundant groups--we may not want to do it this way:
    data = get_matrix_data(cond_ids.map{|i|i.condition_id}.uniq,params[:data_type])
    puts "rendering action at #{Time.now}"
    render :text => as_json(data)
  end
  
  def get_binary_data_for_groups
    puts "in get_binary_data_for_groups action at #{Time.now}"
    group_ids = params[:group_ids].split(",")
    puts "group_ids = "
    pp group_ids
    cond_ids = []
    for group_id in group_ids
      cond_ids += ConditionGrouping.find_by_sql(["select condition_id from condition_groupings where condition_group_id = ? order by sequence",group_id.to_i])
    end
    puts "cond_ids:"
    pp cond_ids
    # silently removes redundant groups--we may not want to do it this way:
    data = get_matrix_data_small(cond_ids.map{|i|i.condition_id}.uniq,params[:data_type])
    headers['Content-type'] = 'application/octet-stream'
    
    puts "rendering action at #{Time.now}"
    render :text => as_binary(data)
    #render :text => "ok"
  end
  
  
  
  def get_data_for_group
    data = get_matrix_data_for_group(params[:group_id],params[:data_type])
    headers['Content-type'] = 'text/plain'
    render :text => as_json(data)
  end
  
  def add_new_relationship_type
    r = RelationshipType.new(:name => params[:name], :inverse => params[:inverse])
    r.save
    render :text => RelationshipType.find(:all, :order => 'name').to_json
  end
  
  def get_user_id
    render :text => session[:user_id]
  end
  
  def get_distinct_tags
    tags = Tag.find_by_sql(["select distinct tag, user_id from tags order by tag"])#.map{|i|i.tag}
    render :text => tags.to_json
  end

  def create_new_relationship
    r = Relationship.new(:relationship_type_id => params[:relationship_type_id], :group1 => params[:group1], :group2 => params[:group2])
    existing = Relationship.find(:first, :conditions => ["relationship_type_id = ? and group1 = ? and group2 = ?", r.relationship_type_id, r.group1, r.group2])
    if (existing.nil?)
      r.save
      render :text => "ok" and return false
    else
      render :text => "duplicate"
    end
  end
  
  def get_related_groups
    group_id = params[:group_id].to_i
    render :text => find_related_groups(group_id).to_json(:methods => [:relationship,:relationship_id])
  end
  
  def get_auto_completion_items
#    res = Condition.find(:all).map{|i|i.name}
#    res += ConditionGroup.find(:all).map{|i|i.name}
    res = SearchTerm.find(:all).map{|i|i.word}
    res.sort!
    res.uniq!
  
    render :text => res.to_json
  end
  
  def delete_relationship
    Relationship.delete(params[:relationship_id])
    render :text => find_related_groups(params[:group_id].to_i).to_json
  end
  
  def rename_group
    group = ConditionGroup.find(params[:group_id])
    group.name = params[:new_name]
    group.save
    render :text => "ok"
  end
  
  def delete_group
    begin
      ConditionGroup.transaction do
        relationships_to_delete = Relationship.find_by_sql(["select id from relationships where group1 = ? or group2 = ?",
          params[:group_id],params[:group_id]]).map{|i|i.id}
        Relationship.delete(relationships_to_delete)
        ConditionGroup.delete(params[:group_id])
      end
      render :text => "ok"
    rescue Exception => ex
      puts ex.message
      puts ex.backtrace
    end
  end
  
  def testmail
    u = User.new(:email => "dtenenbaum@systemsbiology.org")
    UserMailer.deliver_register(u, {:secret_word => "zizzy"})
    render :text => "ok"
  end
  
  def is_duplicate_email
    exists = User.find_by_email(params[:email])
    result = (exists.nil?) ? "no" : "yes"
    render :text => result
  end
  
  def register
    # don't trust the client
    unless (params[:email].downcase =~ /systemsbiology\.org$/)
      render :text => "error: must be a systemsbiology.org email address" and return false
    end

    u = User.new(:first_name => params[:first_name], :last_name => params[:last_name], :email => params[:email],
     :password => params[:password], :last_login_date => Time.now, :validated => false)
    
    render :text => "error: possible duplicate email" and return false unless u.save
    
    
    # send the email
    token = "#{u.email}~~~#{SECRET_SALT}"
    secure = Password::update(token)
    url = url_for(:action => nil, :email => u.email, :token => secure)
    UserMailer.deliver_register(u, {:url => url, :user => u})
    
    puts "url = #{url}"
    render :text => "ok"
  end

  def request_password_refresh
    u = User.find_by_email(params[:email])
    render :text => "no such account" and return false if u.nil?
    token = "#{u.email}~~~#{SECRET_SALT}"
    secure = Password::update(token)
    url = url_for(:action => nil, :email => u.email, :token => secure, :change_password => "true")
    
    UserMailer.deliver_password_refresh(u, {:url => url, :user => u})
    render :text => "ok"
  end
  
  def get_knockout_names
    sql = "select distinct gene from knockouts where gene != 'wild type' order by gene"
    res = Knockout.find_by_sql([sql]).map{|i|i.gene}
    gene_names = Gene.find_by_sql(["select gene_name from genes where name in (?) and gene_name is not null",res]).map{|i|i.gene_name}
    res += gene_names
    render :text => res.sort{|a,b|a.downcase <=> b.downcase}.to_json
  end
  
  def get_env_pert_names
    sql = "select distinct perturbation from environmental_perturbations order by perturbation"
    res = EnvironmentalPerturbation.find_by_sql([sql]).map{|i|i.perturbation}
    render :text => res.to_json
  end
  
  def structured_search
    puts "STRUCTURED SEARCH params:"
    pp params
    env_perts = ActiveSupport::JSON.decode(params[:env_perts]) #if params[:env_perts]
    knockouts = ActiveSupport::JSON.decode(params[:knockouts]) #if params[:knockouts]
    env_perts = nil if env_perts.first == ""
    knockouts = nil if knockouts.first == ""
    
    e = (!env_perts.nil? and !env_perts.empty?)
    k = (!knockouts.nil? and !knockouts.empty?)
    
    #puts "e = #{e}, k = #{k}, env_perts=#{env_perts.join(" ")}, knockouts=#{knockouts.join(" ")} ep.size = #{env_perts.size}"
    #puts "epfs=~#{env_perts.first.strip}~"
    
    genes = Gene.find_by_sql(["select name from genes where gene_name in (?) or name in (?)",knockouts,knockouts]).map{|i|i.name}
    
    include_related_results = (params[:include_related_results] == "true") ? true : false
    refine = params.has_key?(:currently_displayed_ids)
    if (refine)
      currently_displayed_ids = ActiveSupport::JSON.decode(params[:currently_displayed_ids])
      id_map = {}
      for id in currently_displayed_ids
        id_map[id.to_i] = 1
      end
    end
    conds = []
    if (e and !k)
      conds =  Condition.find_by_sql(["select * from conditions where id in (select condition_id from environmental_perturbation_associations where environmental_perturbation_id in (select id from environmental_perturbations where perturbation in (?)))",env_perts])
    elsif (k and !e)
      conds = Condition.find_by_sql(["select * from conditions where id in (select condition_id from knockout_associations where knockout_id in (select id from knockouts where gene in (?)))", genes])
    elsif (k and e)
      if (params[:conjunction] == 'AND')
        conds = Condition.find_by_sql(["select * from conditions where id in (select condition_id from knockout_associations where knockout_id in (select id from knockouts where gene in (?)))  and id in  (select condition_id from environmental_perturbation_associations where environmental_perturbation_id in (select id from environmental_perturbations where perturbation in (?)))", genes, env_perts])
      else
        conds = Condition.find_by_sql(["select * from conditions where id in (select condition_id from knockout_associations where knockout_id in (select id from knockouts where gene in (?)))  or id in  (select condition_id from environmental_perturbation_associations where environmental_perturbation_id in (select id from environmental_perturbations where perturbation in (?)))", genes, env_perts])
      end
    end
    
    if refine
      refined = []
      for cond in conds
        refined.push cond if id_map.has_key?(cond.id)
      end
      conds = refined
    end
    
    
    if (include_related_results)
      group_ids = ConditionGrouping.find_by_sql(["select distinct condition_group_id from condition_groupings where condition_id in (?)",
        conds.map{|i|i.id}.join(",")])
      related_groups = []
      for group_id in group_ids
        related_groups += find_related_groups(group_id)
      end
      
      related_conds = []
      for group in related_groups
        related_conds += find_conditions_for_group(group.id)
      end
      
      tmp = conds + related_conds
      
      conds = tmp.uniq
      
      # find group ids
      # find related groups
      # find conds from those
      # merge them with conds
    end
    
    
    groups = get_groups_for_conditions(conds)
    if (groups.empty?)
      render :text => "none" and return false
    else
      ret = []
      groups.each do |g|
        h = g.attributes
        h['num_results'] = g.num_results
        ret << {"condition_group" => h}
      end
      
      
      
      #render :text => groups.to_json(:methods => :ungrouped_ids)
      render :text => ret.to_json
    end
    
    
    #sorted_conds = sort_conditions_for_time_series(conds)
    
    #sorted_conds = Condition.populate_num_groups(sorted_conds)
    
    
    
    
    #if (sorted_conds.empty?)
    #  puts "sorted conds: no match"
    #  render :text => "none" and return false
    #else
    #  puts "structured search returning #{sorted_conds.size} results"
    #  render :text => sorted_conds.to_json(:methods => :num_groups) and return false
    #end
    

  end
  
  def save_tag
    tag_name = params[:tag_name]
    cond_ids = params[:cond_ids].split(",")
    seq = 1
    
    for cond in cond_ids
      t = Tag.new(:tag => tag_name, :condition_id => cond, :user_id => session[:user_id], :sequence => seq, :auto => false)
      t.save
      seq += 1
      
      s = SearchTerm.new(:word => tag_name, :condition_id => cond, :int_timestamp => Time.now.to_i)
      s.save
      
    end
    
    
    render :text => "ok"
  end
  
  def save_search
    puts "in save_search, input is:\n#{params[:search]}"
    search = ActiveSupport::JSON.decode params[:search]
    # todo - determine whether this is a duplicate
    existing = UserSearch.find_by_name_and_user_id(search['name'], session[:user_id])
    render :text => "duplicate" and return false unless existing.nil?
    free_text_search_terms = (search['isStructured']) ? nil : search['freeTextSearch'].join("~~")
    begin
      UserSearch.transaction do
        user_search = UserSearch.new(:name => search['name'], :is_structured => search['isStructured'], :user_id => session[:user_id],
          :free_text_search_terms => free_text_search_terms)
        user_search.save
        if (search['isStructured'])
          search['subSearches'].each_with_index do |sub_search, i|
            ss = SubSearch.new(:user_search_id => user_search.id, 
              :environmental_perturbation => sub_search['envPert'],
              :knockout => sub_search['knockout'],
              :include_related => search['includeRelated'],
              :refine => search['refine'],
              :last_results_option_selected => search['lastResultsOptionSelected'],
              :sequence => i+1)
            ss.save
          end
        end
      end
    rescue Exception => ex
      puts ex.message
      puts ex.backtrace
    end
    
    
    render :text => "ok"
  end
  
  
  def get_timestamp_from_search_terms
    render :text => SearchTerm.find_by_sql("select max(int_timestamp) as result from search_terms").first.result
  end
  
  def get_saved_searches
    results = UserSearch.find_all_by_user_id session[:user_id], :order => 'name', :include => :sub_searches
    pp results
    render :text => results.to_json(:methods => :sub_searches)
  end
  
  def run_saved_search
    canned_search = ActiveSupport::JSON.decode params[:canned_search]
    puts "canned search:"
    pp canned_search
    
    # determine depth of search
    # canonical view
    
    render :text => "ok"
  end

  def get_condition_info_for_ids
    ids = ActiveSupport::JSON::decode params[:cond_ids]
    conds = Condition.find_by_sql(["select * from conditions where id in (?)",ids])
    render :text => conds.to_json
  end
  
  def get_condition
    cond = Condition.find params[:condition_id] 
    render :text => cond.to_json(:include => [:observations, :growth_media_recipe, :reference_sample, :species, :owner, :importer])
  end
  
  def get_group_description
    render :text => group_description(params[:group_id])
  end
  
  def get_condition_description
    render :text => condition_description(params[:condition_id])
  end
  

  def get_gene_alias_map
    render :text => get_alias_map.to_json
  end
  
  
  def glop
    #qs = query_string.gsub(/&amp;/,"&")
    data_type = ""
    if (params["amp;data_type"])
      data_type = params["amp;data_type"]
    elsif (params["data_type"])
      data_type = params["data_type"]
    end


    
    
    cond_ids = []
    data = ''
    
    if (params[:group_id])
      params[:group_ids] = params[:group_id]
    end
    
    if (params[:group_ids])
      group_ids = params[:group_ids].split(",")
      cond_ids = []
      conds = []
      for group_id in group_ids
        conds += ConditionGrouping.find_by_sql(["select condition_id from condition_groupings where condition_group_id = ? order by sequence",group_id])
      end
      cond_ids = conds.map{|i|i.condition_id}
    elsif (params[:condition_ids])
      cond_ids = params[:condition_ids].split(",")
    end

    #render :text => "ok" and return false if true


    data_filename = get_matrix_data(cond_ids,data_type)

    headers['Content-type'] = 'text/plain'
    
    #render :text => as_matrix(data)
    render_matrix_file(data_filename)
    render :text => "hello"
  end
  
  def get_matrices_for_firegoose
    #qs = query_string.gsub(/&amp;/,"&")
    data_type = ""
    if (params["amp;data_type"])
      data_type = params["amp;data_type"]
    elsif (params["data_type"])
      data_type = params["data_type"]
    end


    
    
    cond_ids = []
    data = ''
    
    if (params[:group_id])
      params[:group_ids] = params[:group_id]
    end
    
    if (params[:group_ids])
      group_ids = params[:group_ids].split(",")
      cond_ids = []
      conds = []
      for group_id in group_ids
        conds += ConditionGrouping.find_by_sql(["select condition_id from condition_groupings where condition_group_id = ? order by sequence",group_id])
      end
      cond_ids = conds.map{|i|i.condition_id}
    elsif (params[:condition_ids])
      cond_ids = params[:condition_ids].split(",")
    end

    #render :text => "ok" and return false if true


    data = get_matrix_data(cond_ids,data_type)

    headers['Content-type'] = 'text/plain'
    
    render :text => as_matrix(data)
  end


  alias :get_matrix :get_matrices_for_firegoose

  
  def import_from_pipeline
    puts "Session user = #{get_email_from_session_user}"
    user = User.find_by_email(get_email_from_session_user)
    puts "about to import with user = #{user.email}"
    tmode = (params[:test_mode] == 'true') ? true : false
    # todo  - stop doing this big fakeout and uncomment the last line of this method!
    
    #group_id = (RAILS_ENV == "production") ? 430 : 313 # comment this out!
    
    #group = ConditionGroup.find(group_id) # comment this out!
    #render :text => group.to_json(:methods => :conditions) # this too!
    render :text => PipelineImporter.import_experiment(params[:sbeams_id], params[:sbeams_timestamp], user, tmode).to_json(:methods => :conditions) # uncomment this!
  end
  
  def get_controlled_vocab_names
    # todo - show only approved
    names = ControlledVocabItem.find(:all, :order => 'name')#.map{|i|i.name}
    render :text => names.to_json
  end
  
  def get_units
    units = Unit.find(:all, :order => :name, :conditions => 'parent_id is not null and name is not null ')#.map{|i|i.name}
#    units.unshift(units.detect{|i|i.name == "None"})
    none = Unit.new()
    none.name = "None"
    none.id = 0
    units.unshift(none)
    render :text => units.to_json
  end
  
  
  def save_condition
    obs = ActiveSupport::JSON.decode(params[:observations])
    puts "obs=\n"
    pp obs
    # todo - actually save the condition
    begin
      Condition.transaction do
        cond = Condition.find params[:id]
        cond.name = params[:name]
        cond.last_updated_by = session[:user_id]
        puts "cond:"
        pp cond
        for ob in obs
          old_ob = Observation.find ob["id"]
          old_ob.name_id = ob["name_id"]
          old_ob.units_id = (ob["units_id"] == 0) ? nil : ob["units_id"]
          old_ob.string_value = ob["string_value"]
          old_ob.is_measurement = ob["is_measurement"]
          old_ob.is_time_measurement = ob["is_time_measurement"] # comment this out?
          begin
            old_ob.int_value = Kernel.Integer(ob["string_value"])
          rescue Exception => ex
            old_ob.int_value = nil
          end
          
          begin
            old_ob.float_value = Kernel.Float(ob["string_value"])
          rescue Exception => ex
            old_ob.float_value = nil
          end
          puts "ob:"
          pp old_ob
          old_ob.save
        end
        
        cond.save
      end
    rescue Exception => ex
      puts ex.message
      puts ex.backtrace
      render :text => "error" and return false
    end
    
    render :text => "ok"
  end
  
  
  def get_tags
    tags = Tag.find_by_sql(["select distinct tag, auto from tags order by tag"])
    render :text => tags.to_json
  end
  
  def delete_tag
    Tag.delete_all(["tag = ?", params[:tag]])
    render :text => "ok"
  end
  
  def rename_tag
    Tag.update_all({:tag => params[:new_name]}, ["tag = ?", params[:old_name]])
    render :text => "ok"
  end
  
  def get_envmap
    ids = params[:condition_ids].split(",")
    headers['Content-type'] = 'text/plain'
    render :text =>  EnvmapHelper.get_envmap(ids)
  end

  def get_colmap
    ids = params[:condition_ids].split(",")
    headers['Content-type'] = 'text/plain'
    render :text =>  ColmapHelper.get_colmap(ids)
  end

  
end

