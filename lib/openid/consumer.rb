require "uri"

require "openid/util"
require "openid/dh"
require "openid/parse"
require "openid/fetchers"
require "openid/association"
require "yadis"

# Everything in this library exists within the OpenID Module.  Users of
# the library should look at OpenID::OpenIDConsumer and/or OpenID::OpenIDServer
module OpenID

  # Code returned when either the of the
  # OpenID::OpenIDConsumer.begin_auth or OpenID::OpenIDConsumer.complete_auth
  # methods return successfully.
  SUCCESS = 'success'

  # Code OpenID::OpenIDConsumer.complete_auth
  # returns when the value it received indicated an invalid login.
  FAILURE = 'failure'

  # Code returned by OpenID::OpenIDConsumer.complete_auth when the
  # OpenIDConsumer instance is in immediate mode and ther server sends back a
  # URL for the user to login with.
  SETUP_NEEDED = 'setup needed'  

  # Code returned by OpenID::OpenIDConsumer.begin_auth when it is unable
  # to fetch the URL given by the user.
  HTTP_FAILURE = 'http failure'

  # Code returned by OpenID::OpenIDConsumer.begin_auth when the page fetched
  # from the OpenID URL doesn't contain the necessary link tags to function
  # as an identity page.
  PARSE_ERROR = 'parse error'


  # This class implements the interface for using the OpenID consumer
  # libary.
  #
  # The only part of the library which has to be used and isn't
  # documented in full here is the store required to create an
  # OpenID::OpenIDConsumer instance.  More on the abstract store type and
  # concrete implementations of it that are provided in the documentation
  # of OpenID::OpenIDConsumer.new 
  #
  # ==Overview
  #
  # The OpenID identity verification process most commonly uses the
  # following steps, as visible to the user of this library:
  #
  # 1. The user enters their OpenID into a field on the consumer's
  #    site, and hits a login button.
  #
  # 2. The consumer site discovers the user's OpenID server using
  #    the YADIS protocol.
  #
  # 3. The consumer site sends the browser a redirect to the
  #    identity server.  This is the authentication request as
  #    described in the OpenID specification.
  #
  # 4. The identity server's site sends the browser a redirect
  #    back to the consumer site.  This redirect contains the
  #    server's response to the authentication request.
  #
  # The most important part of the flow to note is the consumer's site
  # must handle two separate HTTP requests in order to perform the
  # full identity check.
  #
  #
  # ==Library Design
  #
  # The library is designed with the above flow in mind.  The
  # goal is to make it as easy as possible to perform the above steps
  # securely.
  #
  # At a high level, there are two important parts in the consumer
  # library.  The first important part is this class, which contains
  # the public interface to actually use this library.  The second is the
  # OpenID::OpenIDStore class, which describes the
  # interface to use if you need to create a custom method for storing
  # the state this library needs to maintain between requests.
  #
  # In general, the second part is less important for users of the
  # library to know about, as several implementations are provided
  # which cover a wide variety of situations in which consumers may
  # use the library.
  #
  # The OpenIDConsumer class contains two public methods
  # corresponding to the actions necessary in steps 3 and
  # 4 described in the overview.  Use of this library should be as easy
  # as creating an OpenIDConsumer object and calling the methods
  # appropriate for the action the site wants to take.
  #
  #
  # ==Stores and Dumb Mode
  #
  # OpenID is a protocol that works best when the consumer site is
  # able to store some state.  This is the normal mode of operation
  # for the protocol, and is sometimes referred to as smart mode.
  # There is also a fallback mode, known as dumb mode, which is
  # available when the consumer site is not able to store state.  This
  # mode should be avoided when possible, as it leaves the
  # implementation more vulnerable to replay attacks.
  #
  # The mode the library works in for normal operation is determined
  # by the store that it is given.  The store is an abstraction that
  # handles the data that the consumer needs to manage between http
  # requests in order to operate efficiently and securely.
  #
  # Several store implementation are provided, and the interface is
  # fully documented so that custom stores can be used as well. The concrete
  # implementations that are provided allow the consumer site to store
  # the necessary data in several different ways: in the filesystem,
  # or in an SQL database.
  #
  # There is an additional concrete store provided that puts the
  # system in dumb mode.  This is not recommended, as it removes the
  # library's ability to stop replay attacks reliably.  It still uses
  # time-based checking to make replay attacks only possible within a
  # small window, but they remain possible within that window.  This
  # store should only be used if the consumer site has no way to
  # retain data between requests at all.
  #
  #
  # ==Immediate Mode
  #
  # In the flow described above, the user may need to confirm to the
  # identity server that it's ok to authorize his or her identity.
  # The server may draw pages asking for information from the user
  # before it redirects the browser back to the consumer's site.  This
  # is generally transparent to the consumer site, so it is typically
  # ignored as an implementation detail.
  #
  # There can be times, however, where the consumer site wants to get
  # a response immediately.  When this is the case, the consumer can
  # put the library in immediate mode.  In immediate mode, there is an
  # extra response possible from the server, which is essentially the
  # server reporting that it doesn't have enough information to answer
  # the question yet.  In addition to saying that, the identity server
  # provides a URL to which the user can be sent to provide the needed
  # information and let the server finish handling the original
  # request.
  #
  # ==Using the Library
  #
  # Integrating this library into an application is usually a
  # relatively straightforward process.  The process should basically
  # follow this plan:
  #
  # Add an OpenID login field somewhere on your site.  When an OpenID
  # is entered in that field and the form is submitted, it should make
  # a request to the your site which includes that OpenID URL.
  #
  # When your site receives that request, it should create an
  # OpenID::OpenIDConsumer instance, and call
  # OpenID::OpenIDConsumer.begin_auth>.  If begin_auth completes successfully,
  # it will return an OpenID::OpenIDAuthRequest.  Otherwise it will
  # provide some useful information for giving the user an error
  # message.
  #
  # Next, send the user a redirect to the URL provided by
  # OpenIDAuthRequest.redirect_url.
  #
  # That's the first half of the process.  The second half of the
  # process is done after the user's OpenID server sends the user a
  # redirect back to your site to complete their login.
  #
  # When that happens, the user will contact your site at the URL
  # given as the return_to URL you provided to the OpenIDConsumer.begin_auth
  # call made above.  The request will have several query parameters added
  # to the URL by the identity server as the information necessary to
  # finish the request.
  #
  # The next step is to call the OpenID::OpenIDConsumer.complete_auth method
  # with a hash of all the query arguments.  This call will
  # return a status code and some additional information describing
  # the the server's response.  See the documentation for
  # OpenID::OpenIDConsumer.complete_auth for a full
  # explanation of the possible responses.
  #
  # At this point, you have an identity URL that you know belongs to
  # the user who made that request.  Some sites will use that URL
  # directly as the user name.  Other sites will want to map that URL
  # to a username in the site's traditional namespace.  At this point,
  # you can take whichever action makes the most sense.
  #
  # ==OpenID::OpenIDConsumer
  #
  # This class provides the interface to the OpenID consumer logic.
  # Instances maintain no per-request state, so they can be reused (or
  # even used by multiple threads concurrently) as needed.
  class OpenIDConsumer

    # Number of characters to be used in generated nonces
    @@NONCE_LEN = 8
    
    # Nonce character set
    @@NONCE_CHRS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    # Number of seconds the tokens generated by this library will be valid for.
    @@TOKEN_LIFETIME = 60 * 2
    
    public
        
    # Creates a new OpenIDConsumer instance.  You *SHOULD* create a new
    # instance of the OpenIDConsumer object with every HTTP request.  Do not
    # store the instance of it in a global variable somewhere.
    #
    # [+store+] 
    #   This must be an object that implements the OpenIDStore interface.
    #   Several concrete implementations are provided, to cover
    #   most common use cases.  For a filesystem-backed store,
    #   see FilesystemOpenIDStore  
    #
    # [+session+]
    #   A hash-like object representing the user's session data.  This is
    #   used for keeping state of the OpenID transaction when the user is
    #   redirected to the server.  In a rails application, the controller's
    #   @session variable should be passed in for this argument.
    #
    # [+trust_root+]
    #   This is a URL that will be sent to the
    #   server to identify this site.  The OpenID spec (
    #   http://www.openid.net/specs.bml#mode-checkid_immediate )
    #   has more information on what the trust_root value is for
    #   and what its form can be.  While the trust root is
    #   officially optional in the OpenID specification, this
    #   implementation requires that it be set.  Nothing is
    #   actually gained by leaving out the trust root, as you can
    #   get identical behavior by specifying the return_to URL as
    #   the trust root.  
    # 
    # [+fetcher+]
    #   Optional.  If provided, this must be an instance that implements
    #   OpenIDHTTPFetcher interface.  If not fetcher is provided,
    #   a NetHTTPFetcher fetcher will be created for you automatically.
    #
    # [+immediate+]
    #   Optional boolean.  Controls whether the library uses immediate mode, as
    #   explained in the module description.  The default value is false,
    #   which disables immediate mode.    
    def initialize(store, session, trust_root, fetcher=nil, immediate=false)
      if fetcher.nil?
        fetcher = NetHTTPFetcher.new
      end

      @store = store
      @fetcher = fetcher
      @immediate = immediate
      @mode = immediate ? "checkid_immediate" : "checkid_setup"
      @session = session
      @trust_root = trust_root
      @ca_path = nil
    end
    
    # Set the path to a pem certificate authority file for verifying
    # server certificates during HTTPS.  If you are interested in verifying
    # certs like the mozilla web browser, have a look at the files here:
    #
    # http://curl.haxx.se/docs/caextract.html
    def ca_path=(ca_path)
      ca_path = ca_path.to_s
      if File.exists?(ca_path)
        @ca_path = ca_path
        @fetcher.ca_path = ca_path
      else
        raise ArgumentError, "#{ca_path} is not a valid file path"
      end
    end

    # begin_auth is called to start the OpenID login process.
    #
    # ==Parameters
    # [+user_url+]
    #   Identity URL given by the user. begin_auth takes care of
    #   normalizing and resolving and redirects the server might issue. 
    #
    # [+return_to+]
    #   This is the URL that will be included in the
    #   generated redirect as the URL the OpenID server will send
    #   its response to.  The URL passed in must handle OpenID
    #   authentication responses(OpenIDConsumer.complete_auth calls).
    #
    # ==Return Value
    # Returns an array with two elements.  The first element is a status
    # code, and the second element contains additional information about
    # the status and is dependant on the first.
    # 
    # If there was a problem fetching the identity page the user
    # gave, the status code is set to OpenID::HTTP_FAILURE, and
    # the additional information value is either set to nil
    # if the HTTP transaction failed or the HTTP return code,
    # which will be in the 400-500 range. This additional
    # information value may change in a future release.
    # 
    # If the identity page fetched successfully, but didn't
    # include the correct link tags, the status code is set to
    # OpenID::PARSE_ERROR, and the additional information value is
    # currently set to nil.  The additional information
    # value may change in a future release.
    #
    # Otherwise, the status code is set to OpenID::SUCCESS, and
    # the additional information is an instance of
    # OpenIDAuthRequest.  The OpenIDAuthRequest.redirect_url attribute 
    # contains the server URL to which you should redirect the user.
    # The OpenIDAuthRequest.server_url might also be
    # of interest, if you wish to blacklist or whitelist OpenID
    # servers.  You may find out if the OpenID server supports
    # extension you are using through the OpenIDAuthRequest.uses_extension?
    # method.
    #
    # ==Details
    # First, the YADIS protocol is used on the claimed URL to
    # determine their identity server.  If YADIS fails, OpenID 1.1
    # discovery is used to find the OpenID server.  If the page cannot be
    # fetched or if the page does not have the necessary link tags
    # in it, this method returns one of OpenID::HTTP_FAILURE or
    # OpenID::PARSE_ERROR, depending on where the process failed.
    #
    # Second, unless the store provided is a dumb store, it checks
    # to see if it has an association with that identity server, and
    # creates and stores one if not.
    #
    # ==Exceptions
    # This method does not handle any exceptions raised by the store or
    # fetcher it is using.  It raises no exceptions itself.
    def begin_auth(user_url, return_to)
      # normalize url
      begin
        identity_url = OpenID::Util.normalize_url(user_url)
      rescue URI::InvalidURIError
        return [HTTP_FAILURE, nil]
      end
     
      # discover from session (previous yadis)
      status = SUCCESS
      info = session_discovery
           
      # Yadis discovery
      if info.nil?
        status, info = yadis_discovery(identity_url)
      end
      
      # Yadis discovery failed, try OpenID 1.1 discovery
      if status != SUCCESS
        status, info = openid_discovery(identity_url)
      end

      # No more ways to discover. Must bail if we aren't successful by now.
      if status != SUCCESS
        return [status, info]
      end
    
      consumer_id = info.consumer_id
      server_id = info.server_id
      server_url = info.server_url

      # build the nonce and store it
      nonce = OpenID::Util.random_string(@@NONCE_LEN, @@NONCE_CHRS)
      @store.store_nonce(nonce)
    
      # make the token and store it in the session
      token = self.gen_token(nonce, consumer_id, server_id, server_url)
      @session[:_openid_token] = token

      # construct redirect to the server using our discovery information
      redirect_url = self.construct_redirect(server_id, server_url,
                                             return_to, @trust_root)
      
      info = OpenIDAuthRequest.new(token,
                                   server_id,
                                   server_url,
                                   nonce,
                                   redirect_url,
                                   consumer_id,
                                   info.extensions)

      return [SUCCESS, info]
    end
    
    # Called to interpret the server's response to an OpenID request. It
    # is called in step 4 of the flow described in the overview.
    #
    # ==Parameters
    # [+query+]
    #   A hash of the query paramters for this HTTP request.
    #
    # ==Return Value
    # The return value is an array of two elements, consisting of a status and
    # additional information.  The status values are strings, but
    # should be referred to by their symbolic values: OpenID::SUCCESS,
    # OpenID::FAILURE, and OpenID::SETUP_NEEDED.
    #
    # When OpenID::SUCCESS is returned, the additional information
    # returned is either nil or an OpenIDAuthResponse object.  If it is nil, it
    # means the user cancelled the login, and no further information
    # can be determined.
    #
    # If an OpenIDAuthResponse object is returned the identity
    # of ths user making the request has been verified, and their identity
    # URL may be accessed by calling the OpenIDAuthResponse.identity_url
    # method. OpenIDAuthResponse.extension_response exposes an interface for
    # extracting extension response arguments. You may extract simple
    # registration response arguments for example:
    #
    #   openid_auth_response.extension_response(OpenID::SREG)
    # 
    # When OpenID::FAILURE is returned, the additional information is
    # either nil or a string.  In either case, this code means
    # that the identity verification failed.  If it can be
    # determined, the identity that failed to verify is returned.
    # Otherwise nil is returned.
    #
    # When OpenID::SETUP_NEEDED is returned, the additional
    # information is the user setup URL.  This is a URL returned
    # only as a response to requests made with
    # openid.mode=immediate, which indicates that the login was
    # unable to proceed, and the user should be sent to that URL if
    # they wish to proceed with the login.
    #
    # ==Exceptions
    # This method does not handle any exceptions raised by the fetcher or
    # store.  It raises no exceptions itself.
    def complete_auth(query)
      token = @session[:_openid_token]
      @session[:_openid_token] = nil

      mode = query["openid.mode"]
      case mode
      when "cancel"
        return [SUCCESS, nil]
      when "error"
        error = query["openid.error"]
        unless error.nil?
          OpenID::Util.log('Error: '+error)
        end
        return [FAILURE, nil]
      when "id_res"
        code, info = self.do_id_res(token, query)
        @session[:_openid_server_urls] = nil if code == SUCCESS
        return [code, info]
      else
        return [FAILURE, nil]
      end
    end

    # Called to construct the redirect URL sent to
    # the browser to ask the server to verify its identity.  This is
    # called in step 3 of the flow described in the overview.
    # Please note that you don't need to call this method directly
    # unless you need to create a custom redirect, as it is called
    # directly during begin_auth. The generated redirect should be
    # sent to the browser which initiated the authorization request.
    #
    # ==Parameters
    # [+server_id+]
    #   The user's identity URL on the server. This is the
    #   delegate URL if one exists.
    #
    # [+server_url+]
    #   The URL of the user's OpenID server endpoint.
    #
    # [+return_to+]
    #   This is the URL that will be included in the
    #   generated redirect as the URL the OpenID server will send
    #   its response to.  The URL passed in must handle OpenID
    #   authentication responses.
    # 
    # [+trust_root+]
    #   This is a URL that will be sent to the
    #   server to identify this site.  The OpenID spec (
    #   http://www.openid.net/specs.bml#mode-checkid_immediate )
    #   has more information on what the trust_root value is for
    #   and what its form can be.  While the trust root is
    #   officially optional in the OpenID specification, this
    #   implementation requires that it be set.  Nothing is
    #   actually gained by leaving out the trust root, as you can
    #   get identical behavior by specifying the return_to URL as
    #   the trust root.
    #
    # ==Return Value
    # Return a string which is the URL to which you should redirect the user.
    #
    # ==Exceptions
    # This method does not handle exceptions thrown by the store it is using.
    def construct_redirect(server_id, server_url, return_to, trust_root)
      redir_args = {
        "openid.identity" => server_id,
        "openid.return_to" => return_to,
        "openid.trust_root" => trust_root,
        "openid.mode" => @mode
      }

      assoc = self.get_association(server_url)
      redir_args["openid.assoc_handle"] = assoc.handle unless assoc.nil?

      OpenID::Util.append_args(server_url, redir_args).to_s
    end

    protected

    def do_id_res(token, query)
      ret = self.split_token(token)
      return [FAILURE, nil] if ret.nil?
      
      nonce, consumer_id, server_id, server_url = ret

      user_setup_url = query["openid.user_setup_url"]
      unless user_setup_url.nil?
        return [SETUP_NEEDED, user_setup_url]
      end
      
      return_to = query["openid.return_to"]
      server_id2 = query["openid.identity"]
      assoc_handle = query["openid.assoc_handle"]
      
      if return_to.nil? or server_id.nil? or assoc_handle.nil?
        return [FAILURE, consumer_id]
      end

      if server_id != server_id2
        return [FAILURE, consumer_id]
      end
      
      assoc = @store.get_association(server_url)
    
      if assoc.nil?
        # It's not an association we know about. Dumb mode is our
        # only possible path for recovery.
        return [self.check_auth(nonce, query, server_url), consumer_id]
      end

      if assoc.expires_in <= 0
        OpenID::Util.log("Association with #{server_url} expired")
        return [FAILURE, consumer_id]
      end

      # Check the signature
      sig = query["openid.sig"]
      signed = query["openid.signed"]
      return [FAILURE, consumer_id] if sig.nil? or signed.nil?
      
      args = OpenID::Util.get_openid_params(query)
      signed_list = signed.split(",")
      _signed, v_sig = OpenID::Util.sign_reply(args, assoc.secret, signed_list)
      
      return [FAILURE, consumer_id] if v_sig != sig    
      return [FAILURE, consumer_id] unless @store.use_nonce(nonce)
      return [SUCCESS, OpenIDAuthResponse.new(consumer_id, query)]
    end

    def check_auth(nonce, query, server_url)
      check_args = OpenID::Util.get_openid_params(query)
      check_args["openid.mode"] = "check_authentication"
      post_data = OpenID::Util.urlencode(check_args)

      ret = @fetcher.post(server_url, post_data)
      if ret.nil?
        return FAILURE
      else
        url, body = ret
      end
    
      results = OpenID::Util.parsekv(body)
      is_valid = results.fetch("is_valid", "false")
    
      if is_valid == "true"
        invalidate_handle = results["invalidate_handle"]
        unless invalidate_handle.nil?
          @store.remove_association(server_url, invalidate_handle)
        end
        unless @store.use_nonce(nonce)
          return FAILURE
        end
        return SUCCESS
      end
    
      error = results["error"]
      return FAILURE unless error.nil?
      return FAILURE
    end

    def get_association(server_url)
      return nil if @store.dumb?
      assoc = @store.get_association(server_url)
      return assoc unless assoc.nil?
      return self.associate(server_url)    
    end
    
    def gen_token(nonce, consumer_id, server_id, server_url)
      timestamp = Time.now.to_i.to_s
      joined = [timestamp, nonce, consumer_id,
                server_id, server_url].join("\x00")
      sig = OpenID::Util.hmac_sha1(@store.get_auth_key, joined)
      OpenID::Util.to_base64(sig+joined)
    end

    def split_token(token)
      return nil if token.nil?

      token = OpenID::Util.from_base64(token)
      return nil if token.length < 20
      
      sig, joined = token[(0...20)], token[(20...token.length)]
      return nil if OpenID::Util.hmac_sha1(@store.get_auth_key, joined) != sig
      
      s = joined.split("\x00")
      return nil if s.length != 5

      timestamp, nonce, consumer_id, server_id, server_url = s
      
      timestamp = timestamp.to_i
      return nil if timestamp == 0
      return nil if (timestamp + @@TOKEN_LIFETIME) < Time.now.to_i
      
      return [nonce, consumer_id, server_id, server_url].freeze
    end

    # Yadis discovery of server URL.
    def yadis_discovery(identity_url)
      YADIS.ca_path = @ca_path if @ca_path
      begin
        yadis = YADIS.new(identity_url)
      rescue YADISHTTPError
        return [HTTP_FAILURE, nil]      
      rescue YADISParseError
        return [PARSE_ERROR, nil]
      end
      
      infos = []
      yadis.openid_servers.each do |server|
        consumer_id = OpenID::Util.normalize_url(yadis.uri)            
        server_url = OpenID::Util.normalize_url(server.uri)
        
        delegate = server.other['openid:Delegate']
        if delegate.nil?
          server_id = consumer_id
        else
          server_id = OpenID::Util.normalize_url(delegate)
        end

        extensions = []
        server.element.elements.each('openid:Extension') do |e|
          extensions << e.text
        end
          
        infos << DiscoverData.new(consumer_id, server_id,
                                  server_url, extensions)
      end
          
      @session[:_openid_server_urls] = infos
      return [SUCCESS, session_discovery]
    end

    def session_discovery
      # discover from session (previous yadis)
      if @session[:_openid_server_urls]
        status = SUCCESS
        info = @session[:_openid_server_urls].shift
        
        if @session[:_openid_server_urls].length == 0
          @session[:_openid_server_urls] = nil
        end

        return info
      end
      return nil
    end

    # OpenID 1.1 style discovery using
    # <link rel="openid.server" href="http://example.com/server" />
    def openid_discovery(identity_url)
      begin
        url = OpenID::Util.normalize_url(identity_url)
      rescue URI::InvalidURIError
        return [HTTP_FAILURE, nil]
      end
      ret = @fetcher.get(url)
      return [HTTP_FAILURE, nil] if ret.nil?
      
      consumer_id, data = ret
      server = nil
      delegate = nil
      parse_link_attrs(data) do |attrs|
        rel = attrs["rel"]
        if rel == "openid.server" and server.nil?
          href = attrs["href"]
          server = href unless href.nil?
        end
        
        if rel == "openid.delegate" and delegate.nil?
          href = attrs["href"]
          delegate = href unless href.nil?
        end
      end

      return [PARSE_ERROR, nil] if server.nil?
    
      server_id = delegate.nil? ? consumer_id : delegate

      consumer_id = OpenID::Util.normalize_url(consumer_id)
      server_id = OpenID::Util.normalize_url(server_id)
      server_url = OpenID::Util.normalize_url(server)
                  
      return [SUCCESS, DiscoverData.new(consumer_id, server_id, server_url)]
    end    

    def associate(server_url)
      dh = OpenID::DiffieHellman.new
      cpub = OpenID::Util.to_base64(OpenID::Util.num_to_str(dh.public))
      args = {
        'openid.mode' => 'associate',
        'openid.assoc_type' =>'HMAC-SHA1',
        'openid.session_type' =>'DH-SHA1',
        'openid.dh_modulus' => OpenID::Util.to_base64(OpenID::Util.num_to_str(dh.p)),
        'openid.dh_gen' => OpenID::Util.to_base64(OpenID::Util.num_to_str(dh.g)),
        'openid.dh_consumer_public' => cpub
      }
      body = OpenID::Util.urlencode(args)
      
      ret = @fetcher.post(server_url, body)
      return nil if ret.nil?
      url, data = ret
      results = OpenID::Util.parsekv(data)
      
      assoc_type = results["assoc_type"]
      return nil if assoc_type.nil? or assoc_type != "HMAC-SHA1"
      
      assoc_handle = results["assoc_handle"]
      return nil if assoc_handle.nil?    
      
      expires_in = results.fetch("expires_in", "0").to_i

      session_type = results["session_type"]
      if session_type.nil?
        secret = OpenID::Util.from_base64(results["mac_key"])
      else
        return nil if session_type != "DH-SHA1"
        
        dh_server_public = results["dh_server_public"]
        return nil if dh_server_public.nil?
        
        spub = OpenID::Util.str_to_num(OpenID::Util.from_base64(dh_server_public))
        dh_shared = dh.get_shared_secret(spub)
        enc_mac_key = results["enc_mac_key"]
        secret = OpenID::Util.strxor(OpenID::Util.from_base64(enc_mac_key),
                                     OpenID::Util.sha1(OpenID::Util.num_to_str(dh_shared)))
      end
   
      assoc = OpenID::Association.from_expires_in(expires_in, assoc_handle,
                                                  secret, 'HMAC-SHA1')
      @store.store_association(server_url, assoc)
      assoc
    end

  end

  # Internal object that contains server and service discovery information.
  class DiscoverData
    
    attr_reader :consumer_id, :server_id, :server_url, :extensions

    def initialize(consumer_id, server_id, server_url, extensions=nil)
      @consumer_id = consumer_id
      @server_id = server_id
      @server_url = server_url
      
      extensions = [] if extensions.nil?
      @extensions = extensions.collect {|e| OpenID::Util.normalize_url(e)}
    end

  end

  # Encapsulates the information the library retrieves and uses during
  # OpenIDConsumer.begin_auth.
  class OpenIDAuthRequest
    
    attr_reader :token, :server_id, :server_url, :nonce, :redirect_url, :identity_url
    
    # Creates a new OpenIDAuthRequest object.  This just stores each
    # argument in an appropriately named field.
    #
    # Users of this library should not create instances of this
    # class.  Instances of this class are created by OpenIDConsumer
    # during begin_auth.
    def initialize(token, server_id, server_url, nonce,
                   redirect_url, identity_url, extensions)
      @token = token
      @server_id = server_id
      @server_url = server_url
      @nonce = nonce
      @redirect_url = redirect_url
      @identity_url = identity_url
      @extensions = extensions
    end


    # Checks to see if the user's OpenID server supports a given
    # extension, as defined in their Yadis file.  Example:
    #
    #   uses_extension?(OpenID::SREG)
    #   => true
    def uses_extension?(extension_class)
      url = OpenID::Util.normalize_url(extension_class.protocol_url)
      return @extensions.member?(url)
    end

  end

  # Encapsulates the information that is useful after a successful
  # OpenIDConsumer.complete_auth call.  Verified identity URL and
  # signed extension response values are available through this object.
  class OpenIDAuthResponse
    
    attr_reader :identity_url

    # Instances of this object will be created for you automatically
    # by OpenIDConsumer.  You should *never* have to construct this
    # object yourself.
    def initialize(identity_url, query)
      @identity_url = identity_url
      @query = query
    end

    # Returns all the arguments from an extension's namespace.  For example
    # 
    #   openid_auth_response.extension_response(OpenID::SREG)
    # 
    # may return something like:
    #
    #  {'email' => 'mayor@example.com', 'nickname' => 'MayorMcCheese'}
    #
    # The extension namespace is not included in the keys of the returned
    # hash.  Values returned from this method are guaranteed to be signed.
    # Calling this method should be the *only* way you access extension
    # response data!
    def extension_response(extension_class)      
      prefix = extension_class.prefix
      
      signed = @query['openid.signed']
      return nil if signed.nil?
      
      signed = signed.split(',')
      extension_args = {}
      extension_prefix = prefix + '.'
      
      signed.each do |arg|
        if arg.index(extension_prefix) == 0
          query_key = 'openid.'+arg
          extension_args[arg[(1+prefix.length..-1)]] = @query[query_key]
        end
      end
      
      return extension_args
    end

  end
  
end
