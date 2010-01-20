class MainController < ApplicationController
  

  include Util
  include DataOutputHelper
  
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
  
  def get_logged_in_user
    if cookies[:echidna_cookie].nil? or cookies[:echidna_cookie].empty?
      render :text => 'not logged in' and return false
    end
    if session[:user].nil?
      begin
        session[:user] = cookies[:echidna_cookie][:value]
      rescue Exception => ex
        render :text => "not logged in" and return false
      end
    end
    render :text => session[:user]
  end
  
  def login
    cookies[:echidna_cookie] = {:value => params[:email],
      :expires => 1000.days.from_now }
    session[:user] = params['email']
    render :text => params[:email]
  end
  
  def logout
    cookies.delete(:echidna_cookie)
    session[:user] = nil  
    render :text => 'logged out'
  end
  
  #cookies[:gwap2_cookie] = {:value => user.email,
  #  :expires => 1000.days.from_now }
  
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
    
    render :text => sorted_conds.to_json(:methods => :num_groups) 


  end
  
  def remove_conditions_from_group
    ids_to_remove = ActiveSupport::JSON.decode(params[:ids_to_remove])
    records_to_remove = ConditionGrouping.find_by_sql([\
      "select id from condition_groupings where condition_group_id = ? and condition_id in (?)",
      params[:group_id],ids_to_remove]).map{|i|i.id}
    ConditionGrouping.delete(records_to_remove)
    render :text => "ok"
  end
  
  
  def get_all_conditions
    conds = Condition.find :all, :order => 'id'
    sorted_conds = sort_conditions_for_time_series(conds)
    headers['Content-type'] = 'text/plain'
    
    render :text => sorted_conds.to_json(:methods => :num_groups) 
  end
  
  def check_if_group_exists
    group = ConditionGroup.find_by_name params[:group_name]
    render :text => (not group.nil?)
  end
  
  def create_new_group
    ids = ActiveSupport::JSON.decode params[:ids]
    group = ConditionGroup.new(:name => params[:name])
    group.save
    ids.each_with_index {|i,index|ConditionGrouping.new(:condition_id => i, :condition_group_id => group.id, :sequence => index +1).save}
    render :text => group.id
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
    sql=<<"EOF"
    select c.id as id, c.name from conditions c, condition_groupings g
    where g.condition_id = c.id
    and g.condition_group_id = ?
    order by g.sequence
EOF
    conds = Condition.find_by_sql([sql, params[:group_id]])
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
  
  def get_condition_detail
    render :text => Condition.find(params[:condition_id]).parse_name.to_json
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
    sql = "select r.*, t.name, t.inverse from relationships r, relationship_types t where t.id = r.relationship_type_id and  (r.group1 = ? or r.group2 = ?)"
    related_groups = Relationship.find_by_sql([sql, group_id, group_id])
    
    id_map= {}
    
    related_groups.each do |g|
      id_map[g.group1] = 1
      id_map[g.group2] = 1
    end
    
    
    names = ConditionGroup.find_by_sql(["select id, name from condition_groups where id in (?)", id_map.keys])
    names.each do |n|
      id_map[n.id] = n.name
    end

    #pp id_map

    
    related_groups.each do |g|
      if (g.group1 == group_id) 
        g.id = g.group2
        g.relationship = g.inverse
        g.name = id_map[g.group2]
      else
        g.id = g.group1
        g.relationship = g.name
        g.name = id_map[g.group1]
      end
    end
    related_groups.sort! do |a,b|
      a.name <=> b.name
    end
    render :text => related_groups.to_json(:methods => :relationship)
  end

end
