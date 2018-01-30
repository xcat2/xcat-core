#!/usr/bin/env python

class SelfServerException(Exception) :
    pass

class SelfClientException(Exception) :
    def __init__(self, message, code) :
        super(Exception, self).__init__(message)
        self.code = code
