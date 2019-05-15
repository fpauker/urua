# UA4UR

OPC Unified Architecture (OPC UA) server for Universal Robots based on open62541.

## Getting Started

These instructions will get you a copy of the project up and running on your local machine for development and testing purposes. See deployment for notes on how to deploy the project on a live system.

### Prerequisites


```
Universal Robot CB 4 and up
opcua-smart for ruby
```

### Installing

Install open62541 and then opcua-smart for ruby. For details follow the instructions on https://github.com/etm/opcua-smart 
```
git clone https://github.com/open62541/open62541.git
cd open62541
mkdir build
cd build
cmake ..
ccmake ..
make
sudo make install

```

Install opcua-smart for ruby (https://github.com/etm/opcua-smart)
```
gem install opcua
```

## Contributing

Please read [CONTRIBUTING.md](https://gist.github.com/PurpleBooth/b24679402957c63ec426) for details on our code of conduct, and the process for submitting pull requests to us.

## Versioning

We use [SemVer](http://semver.org/) for versioning. For the versions available, see the [tags on this repository](https://github.com/your/project/tags). 

## Authors

* **Florian Pauker** - *robotics and OPC UA* - [fpauker](https://github.com/fpauker)
* **Jürgen Mangler** - *ruby and OPC UA* - [etm](https://github.com/etm)

See also the list of [contributors](https://github.com/your/project/contributors) who participated in this project.

## License

This project is licensed under the GNU Lesser General Public License 3.0 - see the [LICENSE.md](LICENSE.md) file for details

## Acknowledgments

This work has been fundet by the Austrian Center for Digital Production
