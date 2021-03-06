#ifndef __SOCKET_H__
#define __SOCKET_H__

enum{
    MAX_NUM_OF_SOCKETS = 10,
    ROOT_SOCKET_ADDR = 255,
    ROOT_SOCKET_PORT = 255,
    SOCKET_BUFFER_SIZE = 128,
};

enum socket_state{
    CLOSED,
    LISTEN,
    ESTABLISHED,
    SYN_SENT,
    SYN_RCVD,
    FIN_SENT,
    FIN_RCVD,
    FIN_WAIT_1,
    FIN_WAIT_2,
    CLOSE_WAIT,
    LAST_ACK,
    TIME_WAIT,
};



typedef nx_uint8_t nx_socket_port_t;
typedef uint8_t socket_port_t;

// socket_addr_t is a simplified version of an IP connection.
typedef nx_struct socket_addr_t{
    nx_socket_port_t port;
    nx_uint16_t addr;
}socket_addr_t;

typedef struct unAckedPackets{
    int index;  // index in sendBuffer of the first data byte that was sent in this pack
    int ack;
    int seq;
    int lastSent;
    uint8_t * data;
    uint32_t timeOut;
    int bytes;  // number of bytes that the pack contained. Usually 9 bytes per pack
    uint16_t destAddr;
    socket_port_t srcPort;
    socket_port_t destPort;


}unAckedPackets;

// File descripter id. Each id is associated with a socket_store_t
typedef uint8_t socket_t;

// State of a socket.
typedef struct socket_store_t{
    uint8_t flag;
    enum socket_state state;
	bool isSender;	// True if the node is the sender in this connection. False if the node is the receiver in this connection
    // stores the socket fd
    socket_t fd;

    // Stores the window size, total number of packets that can be send without receiving an ack
    uint16_t sndWndSize;	// how many bytes the current node is allowed to send without receiving an ACK. This is one factor that limits how much to send, and when to stop sending

    nx_uint16_t srcAddr;
    socket_port_t src;
    socket_addr_t dest;
	  uint16_t transfer;	// how many bytes should be transferred in total
	  uint16_t numberOfBytesSent;	// Number of bytes sent from current node to the other node
	  uint16_t numberOfBytesSentAndAcked;	//Number of bytes that have been sent from current node to the other node THAT HAVE BEEN ACKNOWLEDGED
    uint32_t seq;	// Sequence number = (index in sendBuff of first byte being sent, or about to be sent) + 1 = (number of bytes in other node's receive buffer) + 1
    uint32_t ack;	// Acknowledgement number  = (index in receiveBuff of next byte to recieve) + 1

    // This is the sender portion.
	  uint8_t sendBuff[SOCKET_BUFFER_SIZE];
    uint32_t timeOut[SOCKET_BUFFER_SIZE]; // stores the timeouts for each packet sent
    uint8_t ackReceived[SOCKET_BUFFER_SIZE];//Sender's boolean array, indicating whether a byte in sendBuff has been ACKed by the receiver. Initially (before the message is sent), this is filled with all 0's. Finally (after all data is sent) this is filled with all 1's. ackReceived[i] is 1 if and only if the "i"th byte in sendBuff has been ACKed, and is 0 otherwise. This gets updated when receiving an ACK packet
    uint8_t lastWritten;
    uint8_t lastAck;	//Number of bytes that have been sent to the other node THAT HAVE BEEN ACKNOWLEDGED
    uint8_t lastSent;	// The index number in the sendBuffer of 1st byte the block that we are sending

    int lowestUnackedSentByte;
    int lastSuccessfulSeq; // records the last seq that was successfully sent and received an ack

    char userName[9];


    // This is the receiver portion
    uint8_t rcvdBuff[SOCKET_BUFFER_SIZE];
    //uint8_t lastRead;
	uint8_t indLastByteReadFromRCVD;	// index of last byte read (and taken out of) the receive buffer by the app using the data
    uint8_t numBytesRcvd;	// how many bytes the current node has received and put into it's receive buffer.
    uint8_t nextExpected;

    uint32_t RTT;
    uint16_t lastSentTime;
    uint8_t theirAdvertisedWindow;	// number of bytes that the other side of connection can receive without overflowing the receive buffer. This is sent from receiver to the sender in the send buffer. So this is how many bytes the sender should send
	// AdvertisedWindow = MaxRcvBuffer - ((NextByteExpected - 1) - LastByteRead )
	// All the buffer space minus the buffer space that’s in use
}socket_store_t;

typedef struct user {
	char name[9];
	socket_t fd;
	socket_store_t * userPtr;
}user;

#endif
