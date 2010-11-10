# vim: set softtabstop=2 shiftwidth=2 expandtab :
# (c) 2009 Zouchaoqun
# (c) 2010 KissCool
require 'rubygems'
require 'socket'
# use Bundler if present
begin
  ENV['BUNDLE_GEMFILE'] = File.join(File.dirname(__FILE__), './Gemfile')
  require 'bundler/setup'
rescue LoadError
end
# let's load the Mongo stuff
require 'mongo'
include Mongo

# some of this code has been derived from Zouchaoqun's ezFtpSearch project
# kuddos to his work

# the code has now become very different than ezFtpSearch


###############################################################################
################### LOAD OF CONFIGURATION

# here we load config options
require File.join(File.dirname(__FILE__), './config.rb')

###############################################################################
################### ORM MODEL CODE (do not edit if you don't know)

#
# the Entry class is a generic class for fields and directories 
class Entry
#  property :id,             Serial
#  field :parent_id,      Integer, :index => true
##  field :entries_count,  :type => Integer, :default => 0, :required => true
##  field :name,           :type => String, :required => true, :length => 255#, :index => true
##  field :size,           :type => Float
##  field :entry_datetime, :type => DateTime
##  field :directory,      :type => Boolean, :default => false, :required => true
##  field :index_version,  :type => Integer, :default => 0, :required => true#, :index => true # will help us avoid duplication during indexing
  #property :ftp_server_id,  Integer, :required => true, :key => true

  # this is the point of entry to every entries
  @@collection = $db['entries']
  def self.collection
    @@collection
  end

  ### methods

  # gives the full path of the directory above the entry
  def ancestors_path
    if parent
      p = ancestors.join('/')
      p + '/'
    else
      ''
    end
  end

  # gives the full path of the entry
  def self.full_path(entry)
    entry['parent_path'].to_s + "/" + entry['name'].to_s
  end

  # gives the remote path of the entry, eg. ftp://host/full_path
  def self.remote_path(entry)
    FtpServer.url(FtpServer.collection.find_one('_id' => entry['ftp_server_id'])) + '/' + self.full_path(entry)
  end

  # no need to explain
  def to_s
    name
  end
  
  def get_size
    size
  end

  # return an array of entries
  def self.search(query)
    Entry.all(:name.like => "%#{query}%", :order => [:ftp_server_id.desc])
  end

  # return an array of entries
  # the params are :
  # query : searched string, in the form of "%foo%bar%"
  # page : offset of the page of results we must return
  # order : order string, in the form of "name", ""size" or "size.desc"
  # online : restrict the query to online FTP servers or to every known ones
  def self.complex_search(query="", page=1, order="ftp_server_id.asc", online=true)
    # here we define how many results we want per page
    per_page = 20

    # basic checks and default options
    query ||= ""
    page  ||= 1
    if page < 1
     page = 1
    end
    order ||= "ftp_server_id.asc"
    online ||= true

    # we build the order object
    #t = order.split('.')
    #build_order = DataMapper::Query::Operator.new(t[0], t[1] || 'asc')

    # we will get the list of FTP _ids we will check
    if online
      ftp_list = FtpServer.collection.find('is_alive' => true).collect {|ftp| ftp['_id']}
    else
      ftp_list = FtpServer.collection.find.collect {|ftp| ftp['_id']}
    end

    # we build the query
    filter = {
      'name' => /#{query}/,
      'ftp_server_id' => {'$in' => ftp_list}
    }
    options = {
      :limit => per_page,
      :skip => (page - 1) * per_page,
      :sort => [:ftp_server_id, 'ascending']
    }

    # we build the base query
    #filter = {
    #  :name.like => "%#{query}%",                       # search an entry through a string
      #:index_version => FtpServer.first(:ftp_server).index_version,   # restrict to current index_version
    #  :links => [FtpServer.relationships[:versions]],   # do a JOIN on index_version
    #  :order => build_order,                            # apply a sort order
    #  :limit => per_page,                               # limit the number of results
    #  :offset => (page - 1) * per_page                  # with the following offset
    #}
    # restrict the query to online FTP server or to every registered FTP servers
    #if online
    #  filter.merge!({ :ftp_server => [:is_alive => true] })
    #end

    # execute the query
    results = Entry.collection.find(filter, options)
    
    # how many pages we will have
    options.delete(:limit)
    options.delete(:skip)
    page_count = (Entry.collection.find(filter, options).count.to_f / per_page).ceil

    # finally we return both informations
    return [ page_count, results ]
  end

end

#
# each server is documented here
class FtpServer
#  property :id,             Serial
#  field :name,           :type => String, :required => true
#  field :host,           :type => String, :required => true 
#  field :port,           :type => Integer, :default => 21, :required => true
#  field :ftp_type,       :type => String, :default => 'Unix', :required => true
#  field :ftp_encoding,   :type => String, :default => 'ISO-8859-1'
#  field :force_utf8,     :type => Boolean, :default => true, :required => true
#  field :login,          :type => String, :default => 'anonymous', :required => true
#  field :password,       :type => String, :default => 'garbage', :required => true
#  field :ignored_dirs,   :type => String, :default => '. .. .svn'
#  field :note,           :type => String
#  field :index_version,  :type => Integer, :default => 0, :required => true # will help us avoid duplication during indexing
#  field :updated_on,     :type => DateTime
#  field :last_ping,      :type => DateTime
#  field :is_alive,       :type => Boolean, :default => false


  # point of entry for every FTP servers
  @@collection = $db['ftp_servers']
  def self.collection
    @@collection
  end

  ## methods ##
  
  # always handy to have one
  def to_s
    "id:#{id} NAME:#{name} HOST:#{host} FTP_TYPE:#{ftp_type} LOGIN:#{login}
     PASSWORD:#{password} IGNORED:#{ignored_dirs} NOTE:#{note}"
  end

  # gives the url of the FTP
  def self.url(ftp_server)
    "ftp://" + ftp_server['host']
  end

  # gives the total size of the whole FTP Server
  def size
    Entry.sum(:size, :ftp_server_id => id, :index_version => index_version, :directory => false)
  end

  # gives the number of files in the FTP
  def number_of_files
    Entry.all(:ftp_server_id => id, :index_version => index_version, :directory => false).count
  end

  # handle the ping scan backend
  def self.ping_scan_result(host, is_alive)
    # fist we check if the host is known in the database
    server = self.collection.find_one({'host' => host})
    if server.nil?
      # if the server doesn't exist
      if is_alive
        # but that he is a FTP server
        # then we create it
        # after a quick reverse DNS resolution
        begin
          name = Socket.getaddrinfo(line, 0, Socket::AF_UNSPEC, Socket::SOCK_STREAM, nil, Socket::AI_CANONNAME)[0][2]
        rescue
          name = "anonymous ftp"
        end
        item = {
          :host       => host,
          :name       => name,
          :port       => 21,
          :ftp_type   => 'Unix',
          :ftp_encoding => 'ISO-8859-1',
          :force_utf8  => true,
          :login     => 'anonymous',
          :password  => 'garbage2',
          :ignored_dirs => '. .. .svn',
          :index_version => 0,          
          :is_alive   => is_alive,
          :last_ping  => Time.now
        }
        self.collection.insert item
      end
    else
      # if the server exists in the database
      # then we update its status
      self.collection.update(
        { "_id" => server["_id"] },
        { "$set" => {
          :is_alive   => is_alive,
          :last_ping  => Time.now
          }
        }
      )
    end
  end

  # this is the method which launch the process to index an FTP server
  def self.get_entry_list(ftp_server ,max_retries = 5)
    require 'net/ftp'
    require 'net/ftp/list'
    require 'iconv'
    require 'logger'
    @max_retries = max_retries.to_i
    BasicSocket.do_not_reverse_lookup = true

    # Trying to open ftp server, exit on max_retries
    retries_count = 0
    begin
      @logger = Logger.new(File.dirname(__FILE__) + '/log/spider.log', 'monthly')
      @logger.formatter = Logger::Formatter.new
      @logger.datetime_format = "%Y-%m-%d %H:%M:%S"
      @logger.info("on #{ftp_server['host']} : Trying ftp server #{ftp_server['name']} (id=#{ftp_server['_id']})")
      ftp = Net::FTP.open(ftp_server['host'], ftp_server['login'], ftp_server['password'])
      ftp.passive = true
    rescue => detail
      retries_count += 1
      @logger.error("on #{ftp_server['host']} : Open ftp exception: " + detail.class.to_s + " detail: " + detail.to_s)
      @logger.error("on #{ftp_server['host']} : Retrying #{retries_count}/#{@max_retries}.")
      if (retries_count >= @max_retries)
        @logger.error("on #{ftp_server['host']} : Retry reach max times, now exit.")
        @logger.close
        exit
      end
      ftp.close if (ftp && !ftp.closed?)
      @logger.error("on #{ftp_server['host']} : Wait 30s before retry open ftp")
      sleep(30)
      retry
    end

    # Trying to get ftp entry-list
    get_list_retries = 0
    begin
      @logger.info("on #{ftp_server['host']} : Server connected")
      start_time = Time.now
      @entry_count = 0
      
      # building the index
      get_list_of(ftp_server, ftp)

      # updating our index_version
      self.collection.update(
        { "_id" => ftp_server["_id"] },
        { "$set" => { :updated_on  => Time.now },
          "$inc" => { :index_version   =>  1 }
        }
      )
      
      # remove old entries from the datastore
      Entry.collection.remove({'ftp_server_id' => ftp_server['_id'], 'index_version' => {'$lte' => ftp_server['index_version']}})
      @logger.info("on #{ftp_server['host']} : Old ftp entries deleted after get entries")

      process_time = Time.now - start_time
      @logger.info("on #{ftp_server['host']} : Finish getting list of server " + ftp_server['name'] + " in " + process_time.to_s + " seconds.")
      @logger.info("on #{ftp_server['host']} : Total entries: #{@entry_count}. #{(@entry_count/process_time).to_i} entries per second.")
    rescue => detail
      get_list_retries += 1
      @logger.error("on #{ftp_server['host']} : Get entry list exception: " + detail.class.to_s + " detail: " + detail.to_s)
      @logger.error("on #{ftp_server['host']} : Retrying #{get_list_retries}/#{@max_retries}.")
      raise if (get_list_retries >= @max_retries)
      retry
    ensure
      ftp.close if !ftp.closed?
      @logger.info("on #{ftp_server['host']} : Ftp connection closed.")
      @logger.close
    end
  end

private

  

  # get entries under parent_path, or get root entries if parent_path is nil
  def self.get_list_of(ftp_server, ftp, parent_path = nil, parents = [])
    ic = Iconv.new('UTF-8', ftp_server['ftp_encoding']) if ftp_server['force_utf8']
    ic_reverse = Iconv.new(ftp_server['ftp_encoding'], 'UTF-8') if ftp_server['force_utf8']

    retries_count = 0
    begin
      entry_list = parent_path ? ftp.list(parent_path) : ftp.list
    rescue => detail
      retries_count += 1
      @logger.error("on #{ftp_server['host']} : Ftp LIST exception: " + detail.class.to_s + " detail: " + detail.to_s)
      @logger.error("on #{ftp_server['host']} : Retrying get ftp list #{retries_count}/#{@max_retries}")
      raise if (retries_count >= @max_retries)
      
      reconnect_retries_count = 0
      begin
        ftp.close if (ftp && !ftp.closed?)
        @logger.error("on #{ftp_server['host']} : Wait 30s before reconnect")
        sleep(30)
        ftp.connect(ftp_server['host'])
        ftp.login(ftp_server['login'], ftp_server['password'])
        ftp.passive = true
      rescue => detail2
        reconnect_retries_count += 1
        @logger.error("on #{ftp_server['host']} : Reconnect ftp failed, exception: " + detail2.class.to_s + " detail: " + detail2.to_s)
        @logger.error("on #{ftp_server['host']} : Retrying reconnect #{reconnect_retries_count}/#{@max_retries}")
        raise if (reconnect_retries_count >= @max_retries)
        retry
      end
      
      @logger.error("on #{ftp_server['host']} : Ftp reconnected!")
      retry
    end

    entry_list.each do |e|
      # Some ftp will send 'total nn' string in LIST command
      # We should ignore this line
      next if /^total/.match(e)

      # usefull for debugging purpose
      #puts "#{@entry_count} #{e}"

      if ftp_server['force_utf8']
        begin
          e_utf8 = ic.iconv(e)
        rescue Iconv::IllegalSequence
          @logger.error("on #{ftp_server['host']} : Iconv::IllegalSequence, file ignored. raw data: " + e)
          next
        end
      end
      entry = Net::FTP::List.parse(ftp_server['force_utf8'] ? e_utf8 : e)

      next if ftp_server['ignored_dirs'].include?(entry.basename)

      @entry_count += 1

      begin
        file_datetime = entry.mtime.strftime("%Y-%m-%d %H:%M:%S")
      rescue => detail3
        puts("on #{ftp_server['host']} : strftime failed, exception: " + detail3.class.to_s + " detail: " + detail3.to_s)
        @logger.error("on #{ftp_server['host']} : strftime failed, exception: " + detail3.class.to_s + " detail: " + detail3.to_s)   
        @logger.error("on #{ftp_server['host']} : raw entry: " + e)
      end
      
      entry_basename = entry.basename.gsub("'","''")
     
      # here we build the document
      # that will be inserted in
      # the datastore
      item = {
        :name => entry_basename,
        :parent_path => parent_path,
        :size => entry.filesize,
        :entry_datetime => file_datetime,
        :directory => entry.dir?,
        :ftp_server_id => ftp_server['_id'],
        :index_version => ftp_server['index_version']+1
      }
      Entry.collection.insert item
      
      if entry.dir?
        ftp_path = (parent_path ? parent_path : '') + '/' +
                          (ftp_server['force_utf8'] ? ic.iconv(entry.basename) : entry.basename)
                          #(ftp_server['force_utf8'] ? ic_reverse.iconv(entry.basename) : entry.basename)
        get_list_of(ftp_server, ftp, ftp_path, parents)
      end
    end
  end


end

