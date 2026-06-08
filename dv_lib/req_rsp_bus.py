from cocotb.triggers import RisingEdge


class ResponseDelayPolicy:
    def __init__(
        self,
        response_delay=None,
        response_latency=0,
        out_of_order_response=False,
        out_of_order_fast_delay=1,
        out_of_order_slow_delay=5,
        out_of_order_period=2,
    ):
        if out_of_order_period < 2:
            raise ValueError("out_of_order_period must be at least 2")
        self.response_delay = response_delay
        self.response_latency = response_latency
        self.out_of_order_response = out_of_order_response
        self.out_of_order_fast_delay = out_of_order_fast_delay
        self.out_of_order_slow_delay = out_of_order_slow_delay
        self.out_of_order_period = out_of_order_period

    def get_delay(self, req, sequence):
        if self.response_delay is not None:
            try:
                return self.response_delay(req, sequence)
            except TypeError:
                return self.response_delay(req)

        if self.out_of_order_response:
            if sequence % self.out_of_order_period == 0:
                return self.out_of_order_slow_delay
            return self.out_of_order_fast_delay

        return self.response_latency


class ReqRspBus:
    def __init__(
        self,
        clk,
        rst_n,
        req_valid,
        req_ready,
        rsp_valid,
        rsp_ready,
        req_signals,
        rsp_signals,
        build_response,
        on_accept=None,
        response_delay=None,
        response_latency=0,
        out_of_order_response=False,
        out_of_order_fast_delay=1,
        out_of_order_slow_delay=5,
        out_of_order_period=2,
    ):
        self.clk = clk
        self.rst_n = rst_n
        self.req_valid = req_valid
        self.req_ready = req_ready
        self.rsp_valid = rsp_valid
        self.rsp_ready = rsp_ready
        self.req_signals = req_signals
        self.rsp_signals = rsp_signals
        self.build_response = build_response
        self.on_accept = on_accept
        self.delay_policy = ResponseDelayPolicy(
            response_delay=response_delay,
            response_latency=response_latency,
            out_of_order_response=out_of_order_response,
            out_of_order_fast_delay=out_of_order_fast_delay,
            out_of_order_slow_delay=out_of_order_slow_delay,
            out_of_order_period=out_of_order_period,
        )
        self.pending = []
        self.accepted = []
        self.responses = []
        self._active_response = None
        self.outstanding = 0
        self.max_outstanding = 0

    def idle(self):
        self.req_ready.value = 0
        self.rsp_valid.value = 0
        for signal in self.rsp_signals.values():
            signal.value = 0

    def reset_activity(self):
        if self.outstanding:
            raise RuntimeError("cannot reset activity while transactions are outstanding")
        self.accepted.clear()
        self.responses.clear()
        self.max_outstanding = 0

    def _sample_request(self):
        return {name: int(signal.value) for name, signal in self.req_signals.items()}

    def _drive_response(self, rsp):
        self.rsp_valid.value = 1
        for name, signal in self.rsp_signals.items():
            signal.value = rsp.get(name, 0)

    def _clear_response(self):
        self.rsp_valid.value = 0
        for signal in self.rsp_signals.values():
            signal.value = 0

    def _response_id(self, rsp):
        return rsp.get("id")

    def _select_ready_response(self):
        selected = None
        for index, item in enumerate(self.pending):
            if item["delay"] > 0:
                continue

            if selected is None:
                selected = index
                continue

            item_id = self._response_id(item["rsp"])
            selected_id = self._response_id(self.pending[selected]["rsp"])
            if item_id is not None and selected_id is not None and item_id > selected_id:
                selected = index

        return selected

    async def run(self):
        self.idle()
        while True:
            await RisingEdge(self.clk)

            if not int(self.rst_n.value):
                self.pending.clear()
                self.accepted.clear()
                self.responses.clear()
                self._active_response = None
                self.outstanding = 0
                self.max_outstanding = 0
                self.idle()
                continue

            self.req_ready.value = 1

            if int(self.req_valid.value) and int(self.req_ready.value):
                req = self._sample_request()
                if self.on_accept is not None:
                    self.on_accept(req)

                rsp = self.build_response(req)
                delay = self.delay_policy.get_delay(req, len(self.accepted))
                self.pending.append({"req": req, "rsp": rsp, "delay": delay})
                self.accepted.append(req.copy())
                self.outstanding += 1
                self.max_outstanding = max(self.max_outstanding, self.outstanding)

            for item in self.pending:
                item["delay"] -= 1

            if int(self.rsp_valid.value):
                if int(self.rsp_ready.value):
                    self.responses.append(self._response_id(self._active_response))
                    self.outstanding -= 1
                    self._active_response = None
                    self._clear_response()
                continue

            selected = self._select_ready_response()
            if selected is not None:
                item = self.pending.pop(selected)
                self._active_response = item["rsp"]
                self._drive_response(item["rsp"])


def MemoryReadTarget(
    clk,
    rst_n,
    memory,
    req_valid,
    req_ready,
    req_id,
    req_addr,
    rsp_valid,
    rsp_ready,
    rsp_id,
    rsp_data,
    **kwargs,
):
    return ReqRspBus(
        clk=clk,
        rst_n=rst_n,
        req_valid=req_valid,
        req_ready=req_ready,
        rsp_valid=rsp_valid,
        rsp_ready=rsp_ready,
        req_signals={
            "id": req_id,
            "addr": req_addr,
        },
        rsp_signals={
            "id": rsp_id,
            "data": rsp_data,
        },
        build_response=lambda req: {
            "id": req["id"],
            "data": memory.read_word(req["addr"]),
        },
        **kwargs,
    )


def MemoryWriteTarget(
    clk,
    rst_n,
    memory,
    req_valid,
    req_ready,
    req_id,
    req_addr,
    req_data,
    rsp_valid,
    rsp_ready,
    rsp_id,
    **kwargs,
):
    return ReqRspBus(
        clk=clk,
        rst_n=rst_n,
        req_valid=req_valid,
        req_ready=req_ready,
        rsp_valid=rsp_valid,
        rsp_ready=rsp_ready,
        req_signals={
            "id": req_id,
            "addr": req_addr,
            "data": req_data,
        },
        rsp_signals={
            "id": rsp_id,
        },
        build_response=lambda req: {
            "id": req["id"],
        },
        on_accept=lambda req: memory.write_word(req["addr"], req["data"]),
        **kwargs,
    )
