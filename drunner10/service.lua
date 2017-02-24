-- drunner service configuration for ROCKETCHAT
-- based on https://raw.githubusercontent.com/RocketChat/Rocket.Chat/develop/docker-compose.yml
-- and https://github.com/docker-library/docs/tree/master/rocket.chat

rccontainer="drunner-${SERVICENAME}"
dbcontainer="drunner-${SERVICENAME}-mongodb"
dbvolume="drunner-${SERVICENAME}-database"
certvolume="drunner-${SERVICENAME}-certvolume"
network="drunner-${SERVICENAME}-network"

-- addconfig( VARIABLENAME, DEFAULTVALUE, DESCRIPTION )
addconfig("MODE","fake","LetsEncrypt mode: fake, staging, production")
addconfig("EMAIL","","LetsEncrypt email")
addconfig("DOMAIN","","Domain for the rocket.chat service")

-- overrideable.
sMode="${MODE}"
sEmail="${EMAIL}"
sDomain="${DOMAIN}"

function start_mongo()
    -- fire up the mongodb server.
    result,output=docker("run",
    "--name",dbcontainer,
    "--network=" .. network ,
    "-v", dbvolume .. ":/data/db",
    "-d","mongo:3.2",
    "--smallfiles",
    "--oplogSize","128",
    "--replSet","rs0")
    result or die("Failed to start mongodb : "..output)
    dockerwait(dbcontainer, "27017") or die("Mongodb didn't respond on port 27017 in the expected timeframe.")

    -- run the mongo replica config
    result=docker("run","--rm",
    "--network=" .. network ,
    "mongo:3.2",
    "mongo",dbcontainer .. "/rocketchat","--eval",
    "rs.initiate({ _id: 'rs0', members: [ { _id: 0, host: 'localhost:27017' } ]})"
    )
    result or die("Mongodb replica init failed")
end

function start_rocketchat()
    -- and rocketchat on port 3000
    result,output=docker("run",
    "--name",rccontainer,
    "--network=" .. network ,
    "--env","MONGO_URL=mongodb://" .. dbcontainer .. ":27017/rocketchat",
    "--env","MONGO_OPLOG_URL=mongodb://" .. dbcontainer .. ":27017/local",
    "-d","rocket.chat")

    result or die("Failed to start rocketchat on port ${PORT} : "..output)
    dockerwait(rccontainer, "3000") or die("Rocketchat didn't respond in the expected timeframe.")
end

function start()
   isdockerrunning(dbcontainer) and die("rocketchat is already running.")

   start_mongo()
   start_rocketchat()
      
   -- use dRunner's built-in proxy to expose rocket.chat over SSL (port 443) on host.
   -- disable timeouts because rocket.chat keeps websockets open for ages.
   proxyenable(sDomain,rccontainer,3000,network,sEmail,sMode,false) or die("Couldn't enable proxy")
end

function stop()
   proxydisable() or print("Couldn't disable proxy")

   dockerstop(rccontainer)
   dockerstop(dbcontainer)
end

function uninstall()
   stop()
   docker("network","rm",network) or print("Unable to remove network")
   -- we retain the database volume
end

function obliterate()
   stop()
   docker("network","rm",network) or print("Unable to remove network")
   dockerdeletevolume(dbvolume) or print("Unable to remove docker volume "..dbvolume)
end

-- install
function install()
   dockerpull("mongo:3.2")
   dockerpull("rocket.chat")
   dockercreatevolume(dbvolume) or die("Couldn't create docker volume "..dbvolume)
   result,output = docker("network","create",network)
   result or die("Couldn't create network "..network.." : "..output)
end

function backup()
   docker("pause",rccontainer)
   docker("pause",dbcontainer)

GAHHH THIS RETURNS A CRESULT NOT TRUE/FALSE.
   dockerbackup(dbvolume)

   docker("unpause",dbcontainer)
   docker("unpause",rccontainer)
end

function restore()
   dockerpull("mongo:3.2")
   dockerpull("rocket.chat")
   dockerrestore(dbvolume)

   result,output = docker("network","create",network)
   result or die("Couldn't create network "..network.." : "..output)

-- set mode to fake for safety!
   setconfig("MODE","fake")
end

function selftest()
   sDomain="travis"
   sEmail="j@842.be"
   sMode="fake"
   print("Starting...")
   start()
   print("Stopping...")
   stop()
   print("Self test complete.")
end

function help()
   return [[
   NAME
      ${SERVICENAME} - Run a rocket.chat server.
      Configure the HTTPS settings (Domain, LetsEncrypt email) before
      starting.

   SYNOPSIS
      ${SERVICENAME} help             - This help
      ${SERVICENAME} configure        - Configure domain, email, mode.
      ${SERVICENAME} start            - Start the service
      ${SERVICENAME} stop             - Stop it

   DESCRIPTION
      Built from ${IMAGENAME}.
   ]]
end
