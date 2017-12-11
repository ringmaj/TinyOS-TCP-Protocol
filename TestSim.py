#! /usr/bin/python
#ANDES Lab - University of California, Merced
#Author: UCM ANDES Lab
#$Author: abeltran2 $
#$LastChangedDate: 2014-08-31 16:06:26 -0700 (Sun, 31 Aug 2014) $

import sys
from TOSSIM import *
from CommandMsg import *

class TestSim:
	# COMMAND TYPES
	CMD_PING = 0
	CMD_NEIGHBOR_DUMP = 1
	CMD_ROUTE_DUMP=3
	CMD_LINKSTATE_DUMP = 2

		#David added these commands. Their number values are copied from command.h
	CMD_TEST_CLIENT=4
	CMD_TEST_SERVER=5
	CMD_KILL=6
	CMD_MSG=7
	CMD_CLIENT_APP=8    #to set up app client
	CMD_SERVER_APP=10	#to set up the app server


	# CHANNELS - see includes/channels.h
	COMMAND_CHANNEL="command";
	GENERAL_CHANNEL="general";

	# Project 1
	NEIGHBOR_CHANNEL="neighbor";
	FLOODING_CHANNEL="flooding";

	# Project 2
	ROUTING_CHANNEL="routing";

	# Project 3
	TRANSPORT_CHANNEL="transport";
	CLEAN_OUTPUT='cleanoutput'

	# Personal Debuggin Channels for some of the additional models implemented.
	HASHMAP_CHANNEL="hashmap";

	FINAL_OUTPUT="finaloutput";


	# Initialize Vars
	numMote=0

	def __init__(self):
		self.t = Tossim([])
		self.r = self.t.radio()

		#Create a Command Packet
		self.msg = CommandMsg()
		self.pkt = self.t.newPacket()
		self.pkt.setType(self.msg.get_amType())

	# Load a topo file and use it.
	def loadTopo(self, topoFile):
		print 'Creating Topo!'
		# Read topology file.
		topoFile = 'topo/'+topoFile
		f = open(topoFile, "r")
		self.numMote = int(f.readline());
		print 'Number of Motes', self.numMote
		for line in f:
			s = line.split()
			if s:
				print " ", s[0], " ", s[1], " ", s[2];
				self.r.add(int(s[0]), int(s[1]), float(s[2]))

	# Load a noise file and apply it.
	def loadNoise(self, noiseFile):
		if self.numMote == 0:
			print "Create a topo first"
			return;

		# Get and Create a Noise Model
		noiseFile = 'noise/'+noiseFile;
		noise = open(noiseFile, "r")
		for line in noise:
			str1 = line.strip()
			if str1:
				val = int(str1)
			for i in range(1, self.numMote+1):
				self.t.getNode(i).addNoiseTraceReading(val)

		for i in range(1, self.numMote+1):
			print "Creating noise model for ",i;
			self.t.getNode(i).createNoiseModel()

	def bootNode(self, nodeID):
		if self.numMote == 0:
			print "Create a topo first"
			return;
		self.t.getNode(nodeID).bootAtTime(1333*nodeID);

	def bootAll(self):
		i=0;
		for i in range(1, self.numMote+1):
			self.bootNode(i);

	def moteOff(self, nodeID):
		self.t.getNode(nodeID).turnOff();

	def moteOn(self, nodeID):
		self.t.getNode(nodeID).turnOn();

	def run(self, ticks):
		for i in range(ticks):
			self.t.runNextEvent()

	# Rough run time. tickPerSecond does not work.
	def runTime(self, amount):
		self.run(amount*1000)

	# Generic Command
	def sendCMD(self, ID, dest, payloadStr):
		self.msg.set_dest(dest);
		self.msg.set_id(ID);
		self.msg.setString_payload(payloadStr)

		self.pkt.setData(self.msg.data)
		self.pkt.setDestination(dest)
		self.pkt.deliver(dest, self.t.time()+5)

	def ping(self, source, dest, msg):
		self.sendCMD(self.CMD_PING, source, "{0}{1}".format(chr(dest),msg));

	def neighborDMP(self, destination):
		self.sendCMD(self.CMD_NEIGHBOR_DUMP, destination, "neighbor command");

	def routeDMP(self, destination):
		self.sendCMD(self.CMD_ROUTE_DUMP, destination, "routing command");

	def linkStateDMP (self, destination):
		self.sendCMD(self.CMD_LINKSTATE_DUMP, destination, "linkstate command");

	def addChannel(self, channelName, out=sys.stdout):
		print 'Adding Channel', channelName;
		self.t.addChannel(channelName, out);




		# David is not actually sure if these next new 3 functions work:

	def cmdTestServer (self, source, port):
		#self.sendCMD (self.CMD_TEST_SERVER, address, port);
		self.sendCMD (self.CMD_TEST_SERVER, source, "{0}".format( chr(port)));
		#Initiates the server at node [address] and binds it to [port]
		#print 'Testing '
		#

	#def cmdTestClient(self, source, dest):
	#	self.sendCMD(self.CMD_TEST_CLIENT, source, "{0}".format(chr(dest)));
	def cmdTestClient (self, source, destination, srcPort, destPort, transfer):
		self.sendCMD(self.CMD_TEST_CLIENT, source, "{0}{1}{2}{3}".format(chr(destination), chr(srcPort), chr(destPort), chr(transfer)));
	#	self.sendCMD (self.CMD_TEST_CLIENT, destination, "client command");

	def cmdClientClose (self, source, destination, srcPort, destPort):
		self.sendCMD (self.CMD_KILL, source, "{0}{1}{2}".format(chr(destination), chr(srcPort), chr(destPort)));
		#self.sendCMD (self.CMD_KILL, destination, "close command");

	def cmdSetAppServer(self, source, port):
		#print("{0}".format(chr(port)));
		self.sendCMD (self.CMD_SERVER_APP, source, "{0}".format(chr(port)));

	def cmdSetAppClient(self, source, destination, srcPort, destPort, username):
		self.sendCMD(self.CMD_CLIENT_APP, source, "{0}{1}{2}{3}".format(chr(destination), chr(srcPort), chr(destPort), username));
		#print("{0}{1}{2}".format(chr(destination), chr(srcPort), chr(destPort)));
		#self.sendCMD(self.CMD_CLIENT_APP, source, "{0}{1}{2}".format(chr(destination), chr(srcPort), chr(destPort)));

	def cmdSendText(self, source, destination, srcPort, destPort, message):
		#print("{0}{1}{2}{3}".format(chr(destination), chr(srcPort), chr(destPort), message));
		self.sendCMD(self.CMD_MSG, source, "{0}{1}{2}{3}".format(chr(destination), chr(srcPort), chr(destPort), message));

		#remember that whitespace matters in python. This file uses spaces but not tabs

def main():
	s = TestSim();
	s.runTime(10);
	s.loadTopo("example.topo");
	s.loadNoise("no_noise.txt");
	s.bootAll();
	s.addChannel(s.TRANSPORT_CHANNEL);
	s.addChannel(s.CLEAN_OUTPUT);
	s.addChannel(s.FINAL_OUTPUT);
	#s.addChannel(s.COMMAND_CHANNEL);
	#s.addChannel(s.GENERAL_CHANNEL);
	#s.addChannel(s.NEIGHBOR_CHANNEL);
	#s.addChannel(s.ROUTING_CHANNEL);


	# s.runTime(10);
	# s.cmdTestServer (2, 4);
	# s.runTime(10);


	# s.cmdSetAppServer(2, 41);	#Set Node 2 as an application server at port 41
	# s.runTime(10);
	# #s.cmdSetAppClient(1, 2, 3, 41);	#Set Node 1 as a n application client, that uses port 3 to use the webapp to connect to server 2 at server port 41
	# s.runTime(10);
	# #s.cmdSendText(1, 2, 2, 4, "Hello");
	# s.runTime(10);


	# s.cmdTestServer (1, 3);
	# s.runTime(10);
	# s.cmdTestServer (1, 4);
	# s.runTime(10);
	#s.cmdTestClient (1, 2, 1, 2);
	# s.cmdTestClient (1, 2, 2, 4, 5);
	# s.runTime(10);
	# #clientclose srcport and destport are backwards
	# s.cmdClientClose (1, 2, 4, 2);
	s.runTime(30);

	username = "acerpa\0\0\0"
	s.runTime(10);
	s.cmdSetAppServer(2, 41);	#Set Node 2 as an application server at port 41
	s.runTime(10);
	s.cmdSetAppClient(1, 2, 3, 41, username);	#Set Node 1 as a n application client, that uses port 3 to use the webapp to connect to server 2 at server port 41
	s.runTime(10);
	s.cmdSendText(1, 2, 2, 4, "Hello");
	s.runTime(10);





	#s.neighborDMP(2);

	#s.linkStateDMP(2);
	#s.runTime(10);
	#s.routeDMP(2);

	#s.runTime(10);
	#s.linkStateDMP(5);
	#s.runTime(10);
	#s.routeDMP(5);
	'''
	s.ping(1, 2, "Hello World");
	s.runTime(10);
	s.ping(1, 3, "Hi!");
	s.runTime(20);
	'''

	#s.runTime(20);
	#s.ping(1,5, "Hi");
	#s.runTime(20);
	#s.neighborDiscover();
	#s.neighborDMP (1);
	#s.routeDMP(1);
	#s.runTime(100);

	#s.runTime(20);

	#s.runTime(20);

if __name__ == '__main__':
	main()
