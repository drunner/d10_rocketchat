-- drunner service configuration for ROCKETCHAT
-- based on https://raw.githubusercontent.com/RocketChat/Rocket.Chat/develop/docker-compose.yml
-- and https://github.com/docker-library/docs/tree/master/rocket.chat

rccontainer="drunner-${SERVICENAME}-rocketchat"
dbcontainer="drunner-${SERVICENAME}-mongodb"
dbvolume="drunner-${SERVICENAME}-database"

addenv("PORT","80","The port to run rocketchat on.")

function start_mongo()
    -- fire up the mongodb server.
    result=docker("run",
    "--name",dbcontainer,
    "-v", dbvolume .. ":/data/db",
    "-d","mongo:3.2",
    "--smallfiles",
    "--oplogSize","128",
    "--replSet","rs0")

    if result~=0 then
      print(dsub("Failed to start mongodb."))
    end

    -- wait until it's available
    result=docker("run","--rm",
    "--link", dbcontainer.. ":db",
    "drunner/rocketchat",
    "/usr/local/bin/waitforit.sh","-h","db","-p","27017","-t","60"
    )

    if result~=0 then
      print(dsub("Mongodb didn't seem to start?"))
    end

    -- run the mongo replica config
    result=docker("run","--rm",
    "--link", dbcontainer.. ":db",
    "mongo:3.2",
    "mongo","db/rocketchat","--eval",
    "rs.initiate({ _id: 'rs0', members: [ { _id: 0, host: 'localhost:27017' } ]})"
    )

    if result~=0 then
      print(dsub("Mongodb replica init failed"))
    end

end

function start_rocketchat()
    -- and rocketchat
    result=docker("run",
    "--name",rccontainer,
    "-p","${PORT}:3000",
    "--link", dbcontainer .. ":db",
    "--env","MONGO_URL=mongodb://db:27017/rocketchat",
    "--env","MONGO_OPLOG_URL=mongodb://db:27017/local",
    "-d","rocket.chat")

    if result~=0 then
      print(dsub("Failed to start rocketchat on port ${PORT}."))
    end
end

function start()
   if (dockerrunning(dbcontainer)) then
      print("rocketchat is already running.")
   else
      start_mongo()
      start_rocketchat()
   end
end

function stop()
  dockerstop(dbcontainer)
  dockerstop(rccontainer)
end

function obliterate()
   stop()
end

function uninstall()
   stop()
end

function update()
  stop()
  dockerpull("mongo:3.2")
  dockerpull("rocket.chat")
  start()
end

function backup()
   docker("pause",rccontainer)
   docker("pause",dbcontainer)

   dockerbackup(dbvolume)

   docker("unpause",dbcontainer)
   docker("unpause",rccontainer)
end

function help()
   return [[
   NAME
      ${SERVICENAME} - Run a rocket.chat server on the given port.

   SYNOPSIS
      ${SERVICENAME} help             - This help
      ${SERVICENAME} configure port   - Set port
      ${SERVICENAME} start            - Make it go!
      ${SERVICENAME} stop             - Stop it

   DESCRIPTION
      Built from ${IMAGENAME}.
   ]]
end
