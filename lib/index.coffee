AWS = require 'aws-sdk'
async = require 'async'
stream = require 'stream'

class SQSReadable extends stream.Readable
  constructor: (options) ->
    {@url, accessKeyId, secretAccessKey, region} = options
    region = 'us-east-1' unless region?
    @sqs = new AWS.SQS({ accessKeyId: accessKeyId, secretAccessKey: secretAccessKey, region: region })

    # When stream let us stop, we keep unsent messages into local buffer.
    @local_buffer = []
    @wait_delete = {}
    
    super { objectMode: true }

  strict: (messages, cb) ->
    toTask = (msg) =>
      return (cb) =>
        @sqs.deleteMessage {
          QueueUrl: @url
          ReceiptHandle: msg.ReceiptHandle
        }, cb

    async.parallel (toTask(msg) for msg in messages), cb

  optimistic: (messages, cb) ->
    for msg in messages
      @sqs.deleteMessage {
        QueueUrl: @url
        ReceiptHandle: msg.ReceiptHandle
      }, -> return

    setImmediate cb

  _read: (size) ->
    while(@local_buffer.length > 0)
      item = @local_buffer.shift()
      return unless @push(item)

    @sqs.receiveMessage {
      QueueUrl: @url
      MaxNumberOfMessages: 10
      VisibilityTimeout: 100
      AttributeNames: [ 'All' ]
    }, (err, resp) =>
      return @push(null) if err?
      return @push(null) unless resp.Messages?
      return @push(null) if resp.Messages.length == 0

      for msg in resp.Messages
        do (msg) =>
          msgid = msg.MessageId
          return if @wait_delete[msgid]
          @wait_delete[msgid] = true

          @local_buffer.push JSON.stringify(msg)
          @sqs.deleteMessage {
            QueueUrl: @url
            ReceiptHandle: msg.ReceiptHandle
          }, (err) =>
            delete @wait_delete[msgid]

      while(@local_buffer.length > 0)
        item = @local_buffer.shift()
        return unless @push(item)

    return

setConfig = (config) ->
  console.log 'setConfig is deprecated, pass credential directly into createReadStream'
  AWS.config.update(config)
  return

createReadStream = (options) -> new SQSReadable(options)

# exported methods
module.exports.setConfig = setConfig
module.exports.createReadStream = createReadStream
