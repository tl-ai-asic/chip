import random


class MemoryModel:
    def __init__(self, data_width=32):
        if data_width % 8 != 0:
            raise ValueError("data_width must be byte aligned")
        self.data_width = data_width
        self.bytes_per_word = data_width // 8
        self._words = {}

    def _word_addr(self, byte_addr):
        if byte_addr % self.bytes_per_word:
            raise ValueError(f"unaligned access at byte address 0x{byte_addr:x}")
        return byte_addr // self.bytes_per_word

    def read_word(self, byte_addr):
        return self._words.get(self._word_addr(byte_addr), 0)

    def write_word(self, byte_addr, data):
        mask = (1 << self.data_width) - 1
        self._words[self._word_addr(byte_addr)] = data & mask

    def load_incrementing(self, base_addr, count, first_value):
        for index in range(count):
            self.write_word(base_addr + index * self.bytes_per_word, first_value + index)

    def load_random(self, base_addr, count, seed):
        rng = random.Random(seed)
        for index in range(count):
            self.write_word(
                base_addr + index * self.bytes_per_word,
                rng.getrandbits(self.data_width),
            )

    def compare_words(self, src_addr, dst_addr, count):
        mismatches = []
        for index in range(count):
            offset = index * self.bytes_per_word
            src_data = self.read_word(src_addr + offset)
            dst_data = self.read_word(dst_addr + offset)
            if src_data != dst_data:
                mismatches.append((index, src_data, dst_data))
        return mismatches
