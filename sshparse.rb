#!/usr/bin/ruby
#require 'opcua/server'

require 'net/ssh'

#parsing file system
#puts 'Manifest'
#programs = Hash.new
ssh = Net::SSH.start( '192.168.56.101', 'ur', password: "easybot" )
url = "/home/ur/ursim-current/programs.UR10"
url2 = ""
folder = ssh.exec!("ls -R "+url).split("\n")
#puts folder
folder.each do |f|
  if f.match(/\/.+/)
    url2 = f.to_s[0..-2]+"/"
    p url2
    p url2.sub(url,"")
  end
  if f.match(/.+urp/)
    p url2.to_s + f
  end
  #programs[folder.to_s] = ssh.exec!( "ls "+url+"/"+f+" | grep .urp" ).split( "\n" )
  #p programs
end
#programs = ssh.exec!( 'ls /home/ur/ursim-current/programs.UR10/UR10EVVA | grep .urp' ).split( "\n" )
ssh.close()
#pff = robot.find(:Programs)
#programs.each do |n|
#  pff.manifest(n[0..-1],pf)
#end
