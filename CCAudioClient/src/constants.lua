local instance = {}

instance.VERSION = "1.0.0-alpha"

instance.MAXIMUM_MEMORY_USAGE = 0.90
instance.AVAILABLE_MEMORY = 1000000 * MAXIMUM_MEMORY_USAGE

instance.SKIP_AMOUNT = 25
instance.NEW_CHUNKS_PERCENTAGE = 0.7

instance.SPEAKER_BUFFER_SIZE = 64 * 1024

instance.SAMPLES_PER_SECOND = 48000

return instance