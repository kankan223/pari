package cache

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/redis/go-redis/v9"
)

// UpstashClient is a RedisClient implementation that talks to Upstash's
// HTTP REST API (port 443) instead of the RESP protocol (port 6389).
// This is required on platforms like Render free tier that block
// outbound connections to non-standard ports.
//
// Reference: https://upstash.com/docs/redis/api
type UpstashClient struct {
	baseURL    string // e.g. "https://clear-raccoon-144102.upstash.io"
	token      string // Upstash REST token
	httpClient *http.Client
}

// NewUpstashClient creates an Upstash HTTP client from a rediss:// URL
// and token. The URL must be the base URL (no trailing slash).
//
// Example:
//
// NewUpstashClient("https://clear-raccoon-144102.upstash.io", "AXxx...")
func NewUpstashClient(baseURL, token string) *UpstashClient {
	return &UpstashClient{
		baseURL: strings.TrimRight(baseURL, "/"),
		token:   token,
		httpClient: &http.Client{
			Timeout: 10 * time.Second,
		},
	}
}

// --- low-level HTTP helpers ---

func (c *UpstashClient) do(ctx context.Context, method, path string, body any) ([]any, error) {
	var reqBody io.Reader
	if body != nil {
		raw, err := json.Marshal(body)
		if err != nil {
			return nil, fmt.Errorf("upstash: marshal: %w", err)
		}
		reqBody = bytes.NewReader(raw)
	}
	req, err := http.NewRequestWithContext(ctx, method, c.baseURL+path, reqBody)
	if err != nil {
		return nil, fmt.Errorf("upstash: new request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+c.token)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("upstash: http: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("upstash: read body: %w", err)
	}

	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("upstash: HTTP %d: %s", resp.StatusCode, string(respBody))
	}

	// Pipeline responses are arrays; single responses are objects.
	// Both must be parsed.
	var parsed any
	if err := json.Unmarshal(respBody, &parsed); err != nil {
		return nil, fmt.Errorf("upstash: decode: %w (body: %s)", err, string(respBody))
	}

	switch v := parsed.(type) {
	case []any:
		return v, nil
	case map[string]any:
		return []any{v}, nil
	default:
		return []any{parsed}, nil
	}
}

func (c *UpstashClient) resultStr(results []any, idx int) string {
	if idx >= len(results) {
		return ""
	}
	m, ok := results[idx].(map[string]any)
	if !ok {
		return fmt.Sprintf("%v", results[idx])
	}
	r, ok := m["result"]
	if !ok {
		return ""
	}
	switch t := r.(type) {
	case string:
		return t
	case float64:
		return strconv.FormatInt(int64(t), 10)
	case bool:
		if t {
			return "1"
		}
		return "0"
	default:
		return fmt.Sprintf("%v", t)
	}
}

func (c *UpstashClient) resultInt(results []any, idx int) (int64, error) {
	s := c.resultStr(results, idx)
	if s == "" {
		return 0, redis.Nil
	}
	n, err := strconv.ParseInt(s, 10, 64)
	if err != nil {
		return 0, fmt.Errorf("upstash: parse int %q: %w", s, err)
	}
	return n, nil
}

func (c *UpstashClient) resultBool(results []any, idx int) (bool, error) {
	s := c.resultStr(results, idx)
	switch s {
	case "1", "OK", "true":
		return true, nil
	case "0", "", "false":
		return false, nil
	default:
		n, err := strconv.ParseInt(s, 10, 64)
		if err != nil {
			return false, nil
		}
		return n > 0, nil
	}
}

// --- RedisClient implementation ---

// Set implements RedisClient.
func (c *UpstashClient) Set(ctx context.Context, key string, value any, ttl time.Duration) *redis.StatusCmd {
	cmd := redis.NewStatusCmd(ctx, "set", key)
	body := map[string]any{"value": fmt.Sprintf("%v", value)}
	path := "/set/" + key
	if ttl > 0 {
		path += "?ex=" + strconv.Itoa(int(ttl.Seconds()))
	}
	results, err := c.do(ctx, http.MethodPost, path, body)
	if err != nil {
		cmd.SetErr(err)
		return cmd
	}
	cmd.SetVal(c.resultStr(results, 0))
	return cmd
}

// Get implements RedisClient.
func (c *UpstashClient) Get(ctx context.Context, key string) *redis.StringCmd {
	cmd := redis.NewStringCmd(ctx, "get", key)
	results, err := c.do(ctx, http.MethodPost, "/get/"+key, nil)
	if err != nil {
		cmd.SetErr(err)
		return cmd
	}
	s := c.resultStr(results, 0)
	if s == "" {
		cmd.SetErr(redis.Nil)
		return cmd
	}
	cmd.SetVal(s)
	return cmd
}

// Del implements RedisClient.
func (c *UpstashClient) Del(ctx context.Context, keys ...string) *redis.IntCmd {
	cmd := redis.NewIntCmd(ctx, "del", keys)
	path := "/del/" + strings.Join(keys, "/")
	results, err := c.do(ctx, http.MethodPost, path, nil)
	if err != nil {
		cmd.SetErr(err)
		return cmd
	}
	n, _ := c.resultInt(results, 0)
	cmd.SetVal(n)
	return cmd
}

// Exists implements RedisClient.
func (c *UpstashClient) Exists(ctx context.Context, keys ...string) *redis.IntCmd {
	cmd := redis.NewIntCmd(ctx, "exists", keys)
	path := "/exists/" + strings.Join(keys, "/")
	results, err := c.do(ctx, http.MethodPost, path, nil)
	if err != nil {
		cmd.SetErr(err)
		return cmd
	}
	n, _ := c.resultInt(results, 0)
	cmd.SetVal(n)
	return cmd
}

// SetNX implements RedisClient.
func (c *UpstashClient) SetNX(ctx context.Context, key string, value any, ttl time.Duration) *redis.BoolCmd {
	cmd := redis.NewBoolCmd(ctx, "setnx", key)
	body := map[string]any{"value": fmt.Sprintf("%v", value)}
	path := "/set/" + key + "?nx=true"
	if ttl > 0 {
		path += "&ex=" + strconv.Itoa(int(ttl.Seconds()))
	}
	results, err := c.do(ctx, http.MethodPost, path, body)
	if err != nil {
		cmd.SetErr(err)
		return cmd
	}
	b, _ := c.resultBool(results, 0)
	cmd.SetVal(b)
	return cmd
}

// Expire implements RedisClient.
func (c *UpstashClient) Expire(ctx context.Context, key string, ttl time.Duration) *redis.BoolCmd {
	cmd := redis.NewBoolCmd(ctx, "expire", key)
	secs := int(ttl.Seconds())
	results, err := c.do(ctx, http.MethodPost, "/expire/"+key+"/"+strconv.Itoa(secs), nil)
	if err != nil {
		cmd.SetErr(err)
		return cmd
	}
	b, _ := c.resultBool(results, 0)
	cmd.SetVal(b)
	return cmd
}

// Pipeline implements RedisClient. Returns an UpstashPipeline that
// accumulates commands and sends them in a single HTTP request to
// Upstash's /pipeline endpoint on Exec().
func (c *UpstashClient) Pipeline() Pipeliner {
	return &UpstashPipeline{client: c}
}

// XAdd implements RedisClient.
func (c *UpstashClient) XAdd(ctx context.Context, a *redis.XAddArgs) *redis.StringCmd {
	cmd := redis.NewStringCmd(ctx, "xadd", a.Stream)

	// Upstash XADD: POST /xadd/{stream} with body = field values.
	// XAddArgs.Values is interface{} — typically map[string]interface{}.
	body := map[string]any{}
	if m, ok := a.Values.(map[string]any); ok {
		for k, v := range m {
			body[k] = fmt.Sprintf("%v", v)
		}
	} else if m, ok := a.Values.(map[string]interface{}); ok {
		for k, v := range m {
			body[k] = fmt.Sprintf("%v", v)
		}
	}
	results, err := c.do(ctx, http.MethodPost, "/xadd/"+a.Stream, body)
	if err != nil {
		cmd.SetErr(err)
		return cmd
	}
	cmd.SetVal(c.resultStr(results, 0))
	return cmd
}

// XRead implements RedisClient.
func (c *UpstashClient) XRead(ctx context.Context, a *redis.XReadArgs) *redis.XStreamSliceCmd {
	cmd := redis.NewXStreamSliceCmd(ctx, "xread", a.Streams)

	// Upstash XREAD: POST /xread with body
	streamsMap := map[string]string{}
	for i, s := range a.Streams {
		if i < len(a.Streams) {
			// Streams are alternating key/id pairs or just keys with "0"
			if i%2 == 0 {
				streamsMap[s] = a.Streams[i+1]
			}
		}
	}
	body := map[string]any{"streams": streamsMap}
	if a.Count > 0 {
		body["count"] = a.Count
	}

	results, err := c.do(ctx, http.MethodPost, "/xread", body)
	if err != nil {
		cmd.SetErr(err)
		return cmd
	}

	// Parse the Upstash XREAD response into XStreamSliceCmd
	// Upstash returns: {"result": [{"stream":"name","messages":[{"id":"...","message":{...}}]}]}
	streams, err := parseXReadResult(results)
	if err != nil {
		cmd.SetErr(err)
		return cmd
	}
	cmd.SetVal(streams)
	return cmd
}

// XDel implements RedisClient.
func (c *UpstashClient) XDel(ctx context.Context, stream string, ids ...string) *redis.IntCmd {
	cmd := redis.NewIntCmd(ctx, "xdel", stream, ids)
	path := "/xdel/" + stream + "/" + strings.Join(ids, "/")
	results, err := c.do(ctx, http.MethodPost, path, nil)
	if err != nil {
		cmd.SetErr(err)
		return cmd
	}
	n, _ := c.resultInt(results, 0)
	cmd.SetVal(n)
	return cmd
}

// XLen implements RedisClient.
func (c *UpstashClient) XLen(ctx context.Context, stream string) *redis.IntCmd {
	cmd := redis.NewIntCmd(ctx, "xlen", stream)
	results, err := c.do(ctx, http.MethodPost, "/xlen/"+stream, nil)
	if err != nil {
		cmd.SetErr(err)
		return cmd
	}
	n, _ := c.resultInt(results, 0)
	cmd.SetVal(n)
	return cmd
}

// XTrimMinID implements RedisClient.
func (c *UpstashClient) XTrimMinID(ctx context.Context, stream, minID string) *redis.IntCmd {
	cmd := redis.NewIntCmd(ctx, "xtrim", stream, "MINID", minID)
	body := map[string]any{"method": "MINID", "threshold": minID}
	results, err := c.do(ctx, http.MethodPost, "/xtrim/"+stream, body)
	if err != nil {
		cmd.SetErr(err)
		return cmd
	}
	n, _ := c.resultInt(results, 0)
	cmd.SetVal(n)
	return cmd
}

// --- Pipeline ---

// UpstashPipeline accumulates commands and sends them via Upstash's
// /pipeline HTTP endpoint on Exec().
type UpstashPipeline struct {
	client   *UpstashClient
	commands []pipelineCmd
}

type pipelineCmdType int

const (
	cmdIncr pipelineCmdType = iota
	cmdExpire
	cmdXAdd
	cmdXTrimMinID
)

type pipelineCmd struct {
	typ    pipelineCmdType
	key    string
	ttl    time.Duration
	xadd   *redis.XAddArgs
	trimID string
}

func (p *UpstashPipeline) Incr(ctx context.Context, key string) *redis.IntCmd {
	cmd := redis.NewIntCmd(ctx, "incr", key)
	p.commands = append(p.commands, pipelineCmd{typ: cmdIncr, key: key})
	return cmd
}

func (p *UpstashPipeline) Expire(ctx context.Context, key string, ttl time.Duration) *redis.BoolCmd {
	cmd := redis.NewBoolCmd(ctx, "expire", key)
	p.commands = append(p.commands, pipelineCmd{typ: cmdExpire, key: key, ttl: ttl})
	return cmd
}

func (p *UpstashPipeline) XAdd(ctx context.Context, a *redis.XAddArgs) *redis.StringCmd {
	cmd := redis.NewStringCmd(ctx, "xadd", a.Stream)
	p.commands = append(p.commands, pipelineCmd{typ: cmdXAdd, key: a.Stream, xadd: a})
	return cmd
}

func (p *UpstashPipeline) XTrimMinID(ctx context.Context, stream, minID string) *redis.IntCmd {
	cmd := redis.NewIntCmd(ctx, "xtrim", stream, "MINID", minID)
	p.commands = append(p.commands, pipelineCmd{typ: cmdXTrimMinID, key: stream, trimID: minID})
	return cmd
}

// Exec sends all accumulated commands to Upstash in a single HTTP POST
// to /pipeline and distributes the results back to the command objects.
func (p *UpstashPipeline) Exec(ctx context.Context) ([]redis.Cmder, error) {
	if len(p.commands) == 0 {
		return nil, nil
	}

	// Build the pipeline request body — array of [command, ...args]
	cmds := make([][]any, 0, len(p.commands))
	for _, c := range p.commands {
		switch c.typ {
		case cmdIncr:
			cmds = append(cmds, []any{"INCR", c.key})
		case cmdExpire:
			cmds = append(cmds, []any{"EXPIRE", c.key, int(c.ttl.Seconds())})
		case cmdXAdd:
			vals := map[string]any{}
			if m, ok := c.xadd.Values.(map[string]any); ok {
				for k, v := range m {
					vals[k] = fmt.Sprintf("%v", v)
				}
			} else if m, ok := c.xadd.Values.(map[string]interface{}); ok {
				for k, v := range m {
					vals[k] = fmt.Sprintf("%v", v)
				}
			}
			cmds = append(cmds, []any{"XADD", c.xadd.Stream, vals})
		case cmdXTrimMinID:
			cmds = append(cmds, []any{"XTRIM", c.key, "MINID", c.trimID})
		}
	}

	results, err := p.client.do(ctx, http.MethodPost, "/pipeline", cmds)
	if err != nil {
		return nil, fmt.Errorf("upstash pipeline: %w", err)
	}

	// Distribute results back to command objects
	cmders := make([]redis.Cmder, 0, len(p.commands))
	for i, c := range p.commands {
		switch c.typ {
		case cmdIncr:
			cmd := redis.NewIntCmd(ctx, "incr", c.key)
			n, _ := p.client.resultInt(results, i)
			cmd.SetVal(n)
			cmders = append(cmders, cmd)
		case cmdExpire:
			cmd := redis.NewBoolCmd(ctx, "expire", c.key)
			b, _ := p.client.resultBool(results, i)
			cmd.SetVal(b)
			cmders = append(cmders, cmd)
		case cmdXAdd:
			cmd := redis.NewStringCmd(ctx, "xadd", c.key)
			cmd.SetVal(p.client.resultStr(results, i))
			cmders = append(cmders, cmd)
		case cmdXTrimMinID:
			cmd := redis.NewIntCmd(ctx, "xtrim", c.key)
			n, _ := p.client.resultInt(results, i)
			cmd.SetVal(n)
			cmders = append(cmders, cmd)
		}
	}
	return cmders, nil
}

// --- Response parsers ---

// parseXReadResult parses the Upstash XREAD response into go-redis
// XStream slice format. Upstash returns:
//
//	{"result": [{"stream":"name","messages":[{"id":"...","message":{...}}]}]}
func parseXReadResult(results []any) ([]redis.XStream, error) {
	if len(results) == 0 {
		return []redis.XStream{}, nil
	}

	// The result may be a single object (one stream) or an array
	top := results[0]
	arr, ok := top.([]any)
	if !ok {
		// Single object — wrap in array
		arr = []any{top}
	}

	var streams []redis.XStream
	for _, item := range arr {
		obj, ok := item.(map[string]any)
		if !ok {
			continue
		}

	streamName := ""
	if s, ok := obj["stream"].(string); ok {
		streamName = s
	}

		messages := []redis.XMessage{}
		if msgs, ok := obj["messages"].([]any); ok {
			for _, msgObj := range msgs {
				msgMap, ok := msgObj.(map[string]any)
				if !ok {
					continue
				}
				xm := redis.XMessage{
					ID:     fmt.Sprintf("%v", msgMap["id"]),
					Values: map[string]any{},
				}
				if message, ok := msgMap["message"].(map[string]any); ok {
					xm.Values = message
				} else if message, ok := msgMap["message"].(map[string]interface{}); ok {
					xm.Values = message
				}
				messages = append(messages, xm)
			}
		}

	streams = append(streams, redis.XStream{
		Stream:   streamName,
		Messages: messages,
	})
	}

	return streams, nil
}
