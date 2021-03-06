class BrecordsController < ApplicationController

  def index
    redirect_to :action => :show, :rectype => '*', :hiddengrid => 'true'
  end
  
  def find
    @rectype = params[:rectype].upcase

    if @rectype == '*'
      @statusList = Blevel.find(:all).map { |level| level.bname }.sort.uniq
    else
      @statusList = Blevel.find(:all,
                                :conditions => "blevels.bobjid = brelprocs.id and brelprocs.id = brelrectypes.bobjid and brelrectypes.bname = '" + @rectype + "'",
                                :joins => ',brelprocs,brelrectypes').map { |level| level.bname }.sort.uniq
    end
    @statusList.unshift('')

    if @rectype == 'PART'
      @typeList = DynList.build_from('IPD_PARTSUBTYPE')
    elsif @rectype == 'DOCUMENT'
      @typeList = DynList.build_from('IPD_DOCSUBTYPE')
    elsif @rectype == 'WORKAUTH'
      @typeList = DynList.build_from('IPD_WORKASUBTYP')
    elsif @rectype == 'SOFTWARE'
      @typeList = DynList.sw_types
    else
      @typeList = []
    end
  end

  def show
    @hiddengrid = params[:hiddengrid] || "false"
    @joins = ''
    uda_ref = 'u0'
    if request.post?
      brecord = params[:brecord]
      @rectype = brecord[:find_rec_brectype].upcase
      condition = Condition.new('id = blatest')  # considero solo l'ultima versione
      latest_rev = false
      name = nil
      cage_code = nil
      brecord.each do |key, value|
        downkey = key.downcase
        case downkey
        when /find_rec_(.+)/
          field = $1
          if field != 'bdesc'
            normalize(value)
          end
          if field == 'name'
            name = value
          elsif field == 'bname1'
            cage_code = value
          else
            if field == 'brecalt' and value[-1,1] == '#'
              value[-1,1] = '*'
              latest_rev = true
            end
            condition.add(field, value)
          end
        when /find_uda_(.+)/
          if !Condition.matches_any(value)
            field = $1.upcase
            uda_ref.next!
            @joins += ',budas ' + uda_ref
            condition.add(uda_ref+'.bname', field)
            condition.add(uda_ref+'.bvalue', value)
            condition << uda_ref+'.bobjid = brecords.id'
          end
        else
          raise "Illegal field name: #{key}"
        end
      end
      if name.nil?
        # Il recname non contiene il Cage Code (es. WORKAUTH)
        condition.add("bname1", cage_code)
      else
        # Il recname contiene il Cage Code (es. PART)
        unless Condition.matches_any(name) && Condition.matches_any(cage_code)
          value = name
          value += ('&' + cage_code) unless cage_code.nil?
          condition.add('brecname', value)
        end
      end
      if latest_rev
        @conditions = "(brectype,brecname,brecalt) IN (SELECT brectype,brecname,MAX(brecalt) FROM brecords#{@joins} WHERE #{condition.to_s} GROUP BY brectype,brecname)"
        @joins = ''
      else
        @conditions = condition.to_s
      end
    else
      @rectype = params[:rectype].upcase
      @conditions = "brectype = '!'"
    end
  end

  def grid_records
    prep_query
    @brecords = Brecord.find :all,
      :order => @order,
      :limit => @limit,
      :offset => @offset,
      :select => "id, brecname, brecalt, breclevel, bdesc, bname1",
      :conditions => @conditions,
      :joins => @joins
        
    # Ricalcolo count solo quando necessario
    if (@conditions == @prev_conditions)
      count = @prev_count
    else
      count = Brecord.count :all, :conditions => @conditions, :joins => @joins
    end

    prep_return_data(count)
    @return_data[:rows] = @brecords.collect{|u| {
      :id => u.id,
      :cell => [
        u.id,
        u.name,
        u.bname1,
        u.brecalt,
        u.breclevel,
        u.bdesc]}}

    # Convert the hash to a json object
    render :text => @return_data.to_json, :layout=>false
  end

  def grid_refs
    prep_query
    @brefs = Bref.resolve_set(@order, @limit, @offset, @conditions)
      
    if (@conditions == @prev_conditions)
      count = @prev_count
    else
      count = Bref.count :all, :conditions => @conditions
    end

    prep_return_data(count)
    @return_data[:rows] = @brefs.collect{|u| {
      :id => u.child_id,
      :cell => [
        u.child_id,
        u.breftype,
        u.brectype,
        u.name,
        u.cage_code,
        u.brecalt,
        u.breclevel,
        u.bdesc,
        u.bquantity]}}

    # Convert the hash to a json object
    render :text => @return_data.to_json, :layout=>false
  end

  def grid_promotions
    prep_query
    @promotions = Bpromotion.find :all,
      :order => @order,
      :limit => @limit,
      :offset => @offset,
      :select => "bpromdate, blevel, brelproc, buser, bdesc",
      :conditions => @conditions
      
    count = Bpromotion.count :all, :conditions => @conditions

    prep_return_data(count)
    id = 1
    @return_data[:rows] = @promotions.collect{|u| {
      :id => id+1,
      :cell => [
        id,
        u.promdate,
        u.blevel,
        u.brelproc,
        u.buser,
        u.bdesc]}}

    # Convert the hash to a json object
    render :text => @return_data.to_json, :layout=>false
  end

  def grid_signoffs
    prep_query
    @signoffs = Bchkhistory.find :all,
      :order => @order,
      :limit => @limit,
      :offset => @offset,
      :select => "bdate, bcommand, bstatus, bname, buser, bdesc",
      :conditions => @conditions
      
    count = Bchkhistory.count :all, :conditions => @conditions

    prep_return_data(count)
    id = 1
    @return_data[:rows] = @signoffs.collect{|u| {
      :id => id+1,
      :cell => [
        id,
        u.date,
        u.bcommand,
        u.bstatus,
        u.bname,
        u.buser,
        u.bdesc]}}

    # Convert the hash to a json object
    render :text => @return_data.to_json, :layout=>false
  end

  def grid_revisions
    prep_query
    @revisions = Brecord.find :all,
      :order => @order,
      :limit => @limit,
      :offset => @offset,
      :select =>"id, brectype, brecname, brecalt, breclevel, bproject, bowner, bpromdate",
      :conditions => @conditions
      
    count = Brecord.count :all, :conditions => @conditions

    prep_return_data(count)
    @return_data[:rows] = @revisions.collect{|u| {
      :id => u.id,
      :cell => [
        u.id,
        u.brecalt,
        u.breclevel,
        u.bproject,
        u.bowner,
        u.promdate]}}

    # Convert the hash to a json object
    render :text => @return_data.to_json, :layout=>false
  end

  def load_record_base
    @record = Brecord.find(params[:id])
    if (TABS["#{@record.brectype}"])
      @tabs = (render_to_string :partial => 'tabs', :locals => {:record => @record}).gsub!(/(\n|\r)/,'')
    else
      @tabs = ""
    end
    respond_to do |format|
      format.js
    end
  end

  def load_record_refs
  end

  def load_record_history
    @record = Brecord.find(params[:id])
  end

private

  def normalize(string)
    string ||= ''
    string.sub!(/ +$/,'')
    string.sub!(/^$/,'*')
    string.upcase!
    return string
  end

  def prep_query
    page = (params[:page] || 1).to_i
    @limit = (params[:rows]).to_i
    sidx = params[:sidx]
    sord = params[:sord] || 'asc'
    @order = sidx + ' ' + sord
    @conditions = params[:conditions]
    @joins = params[:joins]

    @prev_conditions = session[:prev_conditions] || ''
    @prev_count = session[:prev_count].to_i
    prev_limit = session[:prev_limit].to_i

    if (prev_limit != @limit)
      page = 1
    end
    @offset = ((page-1) * @limit).to_i
    if (@offset < 0)
      @offset = 0
    end

    isSearch     = params[:_search]
    searchField  = params[:searchField]
    searchOper   = params[:searchOper]
    searchString = params[:searchString]

    if searchField != 'bdesc'
      searchString.upcase! if searchString
    end
    if (isSearch == 'true')
      if (searchOper == 'eq')
        oper = "= '" + searchString +"'"
      elsif (searchOper == 'bw')
        oper = "LIKE '" + searchString + "%'"
      elsif (searchOper == 'ne')
        oper = "<> '" + searchString +"'"
      elsif (searchOper == 'lt')
        oper = "< '" + searchString +"'"
      elsif (searchOper == 'le')
        oper = "<= '" + searchString +"'"
      elsif (searchOper == 'gt')
        oper = "> '" + searchString +"'"
      elsif (searchOper == 'ge')
        oper = ">= '" + searchString +"'"
      elsif (searchOper == 'ew')
        oper = "LIKE '%" + searchString +"'"
      elsif (searchOper == 'cn')
        oper = "LIKE '%" + searchString +"%'"
      end

      @conditions += ' AND ' + searchField + ' ' + oper
      #puts '----> conditions: ' + @conditions
    end

    # Init a hash for the ActiveRecord result
    @return_data = Hash.new()
    @return_data[:page] = page
    @return_data[:total] = 0
    @return_data[:records] = 0
  end

  def prep_return_data(count)
    session[:prev_conditions] = @conditions
    session[:prev_count] = count.to_s
    session[:prev_limit] = @limit.to_s

    total_pages = (count.to_f/@limit).ceil

    # Construct a hash from the ActiveRecord result
    @return_data[:total] = total_pages
    @return_data[:records] = count
  end

end
