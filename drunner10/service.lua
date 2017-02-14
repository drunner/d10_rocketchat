-- drunner service configuration for ROCKETCHAT
-- based on https://raw.githubusercontent.com/RocketChat/Rocket.Chat/develop/docker-compose.yml
-- and https://github.com/docker-library/docs/tree/master/rocket.chat

rccontainer="drunner-${SERVICENAME}-rocketchat"
dbcontainer="drunner-${SERVICENAME}-mongodb"
caddycontainer="drunner-${SERVICENAME}-caddy"
dbvolume="drunner-${SERVICENAME}-database"
certvolume="drunner-${SERVICENAME}-certvolume"
network="drunner-${SERVICENAME}-network"

-- addconfig( VARIABLENAME, DEFAULTVALUE, DESCRIPTION )
addconfig("PORT","443","The port to run rocketchat on.")
addconfig("SUBNETTRIO","10.200.77","First three parts of ip quad. Must be different for each running rocketchat instance.")

function start_mongo()
    -- fire up the mongodb server.
    result=docker("run",
    "--name",dbcontainer,
    "--network=" .. network ,
    "-v", dbvolume .. ":/data/db",
    "-d","mongo:3.2",
    "--smallfiles",
    "--oplogSize","128",
    "--replSet","rs0")

    if result~=0 then
      print("Failed to start mongodb.")
    end

-- Wait for port 27017 to come up in dbcontainer.
    if not dockerwait(dbcontainer, "27017") then
      print("Mongodb didn't seem to start?")
    end

    -- run the mongo replica config
    result=docker("run","--rm",
    "--network=" .. network ,
    "--ip=${SUBNETTRIO}.10",
    "mongo:3.2",
    "mongo",dbcontainer .. "/rocketchat","--eval",
    "rs.initiate({ _id: 'rs0', members: [ { _id: 0, host: 'localhost:27017' } ]})"
    )

    if result~=0 then
      print("Mongodb replica init failed")
    end

end

function start_rocketchat()
    -- and rocketchat
    result=docker("run",
    "--name",rccontainer,
    "-p","80:3000",
    "--network=" .. network ,
    "--ip=${SUBNETTRIO}.11",
    "--env","MONGO_URL=mongodb://" .. dbcontainer .. ":27017/rocketchat",
    "--env","MONGO_OPLOG_URL=mongodb://" .. dbcontainer .. ":27017/local",
    "-d","rocket.chat")

    if result~=0 then
      print("Failed to start rocketchat on port ${PORT}.")
    end
end

function start_caddy()
  result=docker("run",
    "--name",caddycontainer,
    "--network=" .. network ,
    "--ip=${SUBNETTRIO}.12",
    "-p","${PORT}:443",
    "-v", certvolume .. ":/root/.caddy",
  )

-- bridge to outside world.
   docker("network","connect","bridge",caddycontainer)

end

function start()
   if (dockerrunning(dbcontainer)) then
      print("rocketchat is already running.")
   else
      start_mongo()
      start_rocketchat()
      start_caddy()
   end
end

function stop()
  dockerstop(dbcontainer)
  dockerstop(rccontainer)
  dockerstop(caddycontainer)
end

function uninstall()
   stop()
   -- we retain the database volume
end

function obliterate()
   stop()
   dockerdeletevolume(dbvolume)
   dockerdeletevolume(certvolume)
   docker("network","rm",network)
end

-- install
function install()
  dockerpull("mongo:3.2")
  dockerpull("rocket.chat")
  dockerpull("zzrot/alpine-caddy")
  dockercreatevolume(dbvolume)
  dockercreatevolume(certvolume)
  docker("network","create","--subnet=${SUBNETTRIO}.0/24","--gateway=${SUBNETTRIO}.1",network)
--  start() ?
end

function backup()
   docker("pause",rccontainer)
   docker("pause",dbcontainer)

   dockerbackup(dbvolume)
   dockerbackup(certvolume)

   docker("unpause",dbcontainer)
   docker("unpause",rccontainer)
end

function restore()
   dockerrestore(dbvolume)
   dockerrestore(certvolume)
end

function help()
   return [[
   NAME
      ${SERVICENAME} - Run a rocket.chat server on port ${PORT}.

   SYNOPSIS
      ${SERVICENAME} help             - This help
      ${SERVICENAME} configure port   - Set port
      ${SERVICENAME} start            - Make it go!
      ${SERVICENAME} stop             - Stop it

   DESCRIPTION
      Built from ${IMAGENAME}.
   ]]
end
