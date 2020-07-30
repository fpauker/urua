<img align="right" height="100" src="https://github.com/fpauker/urua/blob/master/logo/urua_logo.png">

# URUA 

OPC UA Server for Universal Robots

## Getting Started

A simple ruby server, which uses the ur-sock and opcua-smart library.

### Prerequisites & Intallation

To run the server we need the following packages:

* ruby gems:
```
gem install urua
```

If you want to develop or extend the server, just use the following instruction
```
git clone https://github.com/fpauker/urua
git clone https://github.com/fpauker/ur-sock
git clone https://github.com/etm/opcua-smart
```

Just follow the install instructions of the 3 projects.
After installing all packages do 

```
cd urua/server
```
in this directory the devserver.rb and the devserver.config are located. 

### Starting the server

To start the server type in the following commands:

```
cd urua/server
./uruaserver.rb start
```
or 
```
cd urua/server
./devserver.rb start 
```
to start the developing server.


## Adress space

![Architecture](https://github.com/fpauker/urua/blob/master/adressspace/ur1.png?raw=true)
![Architecture](https://github.com/fpauker/urua/blob/master/adressspace/ur2.png?raw=true)
![Architecture](https://github.com/fpauker/urua/blob/master/adressspace/ur3.png?raw=true)
![Architecture](https://github.com/fpauker/urua/blob/master/adressspace/ur5.png?raw=true)

## Contributing

Please read [CONTRIBUTING.md](https://gist.github.com/PurpleBooth/b24679402957c63ec426) for details on our code of conduct, and the process for submitting pull requests to us.

## Versioning

We use [SemVer](http://semver.org/) for versioning. For the versions available, see the [tags on this repository](https://intra.acdp.at/gogs/fpauker/ua4ur/tags).

## Authors

* **Florian Pauker** - *OPC UA Modelling* -
* **Jürgen Mangler** - *Ruby Support* -

See also the list of [contributors](https://intra.acdp.at/gogs/fpauker/ua4ur/contributors) who participated in this project.

## License

This project is licensed under the GPL3 License - see the [LICENSE.md](./LICENSE) file for details

## Acknowledgments

* This work has been funded by the FFG
