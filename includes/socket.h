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
    int index;
    int ack;
    uint32_t timeOut;
    int bytes;
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
    uint16_t sndWndSize;

    nx_uint16_t srcAddr;
    socket_port_t src;
    socket_addr_t dest;
	uint8_t transfer;	// how many bytes should be transferred in total
	uint8_t numberOfBytesSent;	// Number of bytes sent from current node to the other node
	uint8_t numberOfBytesSentAndAcked;	//Number of bytes that have been sent from current node to the other node THAT HAVE BEEN ACKNOWLEDGED
    uint32_t seq;	// Sequence number = (index in sendBuff of first byte being sent, or about to be sent) + 1 = (number of bytes in other node's receive buffer) + 1
    uint32_t ack;	// Acknowledgement number  = (index in receiveBuff of next byte to recieve) + 1

    // This is the sender portion.
	uint8_t sendBuff[SOCKET_BUFFER_SIZE];
    uint32_t timeOut[SOCKET_BUFFER_SIZE]; // stores the timeouts for each packet sent
    uint8_t ackReceived[SOCKET_BUFFER_SIZE];//Sender's boolean array, indicating whether a byte in sendBuff has been ACKed by the receiver. Initially (before the message is sent), this is filled with all 0's. Finally (after all data is sent) this is filled with all 1's. ackReceived[i] is 1 if and only if the "i"th byte in sendBuff has been ACKed, and is 0 otherwise. This gets updated when receiving an ACK packet
    uint8_t lastWritten;
    uint8_t lastAck;	//Number of bytes that have been sent to the other node THAT HAVE BEEN ACKNOWLEDGED
    uint8_t lastSent;	//Number of bytes that have been sent to the other node

    int lowestUnackedSentByte;
    int lastSuccessfulSeq; // records the last seq that was successfully sent and received an ack


    // This is the receiver portion
    uint8_t rcvdBuff[SOCKET_BUFFER_SIZE];
    uint8_t lastRead;
    uint8_t lastRcvd;
    uint8_t nextExpected;

    uint32_t RTT;
    uint16_t lastSentTime;
    uint8_t effectiveWindow;

}socket_store_t;

#endif
