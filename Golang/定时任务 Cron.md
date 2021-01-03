## 定时任务 Cron

### 任务定义

````go
// 定时任务
type Cron struct {
   entries   []*Entry          // 任务上下文数组
   chain     Chain             // 任务装饰，怎么让任务去执行
   stop      chan struct{}     // 停止任务信号
   add       chan *Entry       // 添加任务信号
   remove    chan EntryID      // 移除任务信号
   snapshot  chan chan []Entry // 任务快照
   running   bool              // 是否在运行
   logger    Logger            // 任务日志
   runningMu sync.Mutex        // 互斥锁
   location  *time.Location    // 当前时间
   parser    ScheduleParser    // 解析器
   nextID    EntryID           // 下一个任务 ID
   jobWaiter sync.WaitGroup    // 优雅退出
}
````



### 任务上下文数组

```go
// 任务上下文数组
type Entry struct {
	ID         EntryID   // 任务ID
	Schedule   Schedule  // 进度表
	Next       time.Time // 下一次定时任务运行时间
	Prev       time.Time // 最后一次运行任务的时间
	WrappedJob Job       // 当计划被激活是要跑的任务 修饰任务
	Job        Job       // 用户本身任务
}
```

## 执行流程

```go
func (c *Cron) run() {
   c.logger.Info("start")
 
   // 为每个任务计算下一个激活时间。
   now := c.now()
   for _, entry := range c.entries {
      entry.Next = entry.Schedule.Next(now)
      c.logger.Info("schedule", "now", now, "entry", entry.ID, "next", entry.Next)
   }
 
   for {
      // 确定要运行的下一个任务
      sort.Sort(byTime(c.entries))
 
      var timer *time.Timer
      if len(c.entries) == 0 || c.entries[0].Next.IsZero() {
         // 如果还没有条目，只需睡眠-它仍然处理新条目 和 停止请求
         timer = time.NewTimer(100000 * time.Hour)
      } else {
         // Sub 子返回持续时间如果结果超过了可以存储在一个持续时间内的最大值（或最小值），则将返回最大（或最小）持续时间。
         // 要计算t-d的持续时间d，使用t。添加（-D）。
         timer = time.NewTimer(c.entries[0].Next.Sub(now))
      }
 
      for {
         select {
         case now = <-timer.C:
            now = now.In(c.location)
            c.logger.Info("wake", "now", now)
 
            // Run every entry whose next time was less than now
            for _, e := range c.entries {
                // 零度报告是否代表零时间瞬间，
               if e.Next.After(now) || e.Next.IsZero() {
                  break
               }
               // 开启任务 封装好的执行任务
               c.startJob(e.WrappedJob)
              // 将写一个任务放入上下文
               e.Prev = e.Next
               e.Next = e.Schedule.Next(now)
               c.logger.Info("run", "now", now, "entry", e.ID, "next", e.Next)
            }
 
         break
      }
   }
 }
  
// 开启一个新的 gourtine 执行任务  
func (c *Cron) startJob(j Job) {
  	c.jobWaiter.Add(1)
	  go func() {
		    defer c.jobWaiter.Done()
		    j.Run()
	  }()
}
  
type Job interface {
	Run()
}
```





## 时间规则

与Linux 中`crontab`命令相似，`cron`库支持用 **5** 个空格分隔的域来表示时间。这 5 个域含义依次为：

- `Minutes`：分钟，取值范围`[0-59]`，支持特殊字符`* / , -`；
- `Hours`：小时，取值范围`[0-23]`，支持特殊字符`* / , -`；
- `Day of month`：每月的第几天，取值范围`[1-31]`，支持特殊字符`* / , - ?`；
- `Month`：月，取值范围`[1-12]`或者使用月份名字缩写`[JAN-DEC]`，支持特殊字符`* / , -`；
- `Day of week`：周历，取值范围`[0-6]`或名字缩写`[JUN-SAT]`，支持特殊字符`* / , - ?`。

 

特殊字符含义如下：

- `*`：使用`*`的域可以匹配任何值，例如将月份域（第 4 个）设置为`*`，表示每个月；
- `/`：用来指定范围的**步长**，例如将小时域（第 2 个）设置为`3-59/15`表示第 3 分钟触发，以后每隔 15 分钟触发一次，因此第 2 次触发为第 18 分钟，第 3 次为 33 分钟。。。直到分钟大于 59；
- `,`：用来列举一些离散的值和多个范围，例如将周历的域（第 5 个）设置为`MON,WED,FRI`表示周一、三和五；
- `-`：用来表示范围，例如将小时的域（第 1 个）设置为`9-17`表示上午 9 点到下午 17 点（包括 9 和 17）；
- `?`：只能用在月历和周历的域中，用来代替`*`，表示每月/周的任意一天。



## 预定义时间规则

- `@yearly`：也可以写作`@annually`，表示每年第一天的 0 点。等价于`0 0 1 1 *`；
- `@monthly`：表示每月第一天的 0 点。等价于`0 0 1 * *`；
- `@weekly`：表示每周第一天的 0 点，注意第一天为周日，即周六结束，周日开始的那个 0 点。等价于`0 0 * * 0`；
- `@daily`：也可以写作`@midnight`，表示每天 0 点。等价于`0 0 * * *`；
- `@hourly`：表示每小时的开始。等价于`0 * * * *`。



## 固定时间规则

```go
@every <duration>
```



## 时区选择

```go
  nyc, _ := time.LoadLocation("America/New_York")
  c := cron.New(cron.WithLocation(nyc))
```

通过 `time.loadLocation`设置当前时区，在启动定时器的时候使用 `cron.WithLocation()` 设置时区时间。



### 任务包装

#### Recover 

```go
func Recover(logger Logger) JobWrapper {
	return func(j Job) Job {
		return FuncJob(func() {
			defer func() {
				if r := recover(); r != nil {
					const size = 64 << 10
					buf := make([]byte, size)
					buf = buf[:runtime.Stack(buf, false)]
					err, ok := r.(error)
					if !ok {
						err = fmt.Errorf("%v", r)
					}
					logger.Error(err, "panic", "stack", "...\n"+string(buf))
				}
			}()
			j.Run()
		})
	}
}
```



```go
// 延迟仍然运行
// 序列化作业，延迟后续运行直到 前一个是完整的。一分钟多后的工作 有延迟登录信息。
func DelayIfStillRunning(logger Logger) JobWrapper {
	return func(j Job) Job {
		var mu sync.Mutex
		return FuncJob(func() {
			start := time.Now()
			mu.Lock()
			defer mu.Unlock()
			if dur := time.Since(start); dur > time.Minute {
				logger.Info("delay", "duration", dur)
			}
			j.Run()
		})
	}
}
```



```go
// SkipifStillrunning 延迟跳过了作业调用
// 如果先前的调用仍在运行。它的日志跳过了给定的Logger在信息水平。
func SkipIfStillRunning(logger Logger) JobWrapper {
	return func(j Job) Job {
		var ch = make(chan struct{}, 1)
		ch <- struct{}{}
		return FuncJob(func() {
			select {
			case v := <-ch:
				j.Run()
				ch <- v
			default:
				logger.Info("skip")
			}
		})
	}
}
```



注意`DelayIfStillRunning`与`SkipIfStillRunning`是有本质上的区别的，前者`DelayIfStillRunning`只要时间足够长，所有的任务都会按部就班地完成，只是可能前一个任务耗时过长，导致后一个任务的执行时间推迟了一点。`SkipIfStillRunning`会跳过一些执行。

- `Recover`：捕获内部`Job`产生的 panic；
- `DelayIfStillRunning`：触发时，如果上一次任务还未执行完成（耗时太长），则等待上一次任务完成之后再执行；
- `SkipIfStillRunning`：触发时，如果上一次任务还未完成，则跳过此次执行。



Demo:

```go
func (d *delayJob) Run() {
	time.Sleep(2 * time.Second)
	d.count++
	log.Printf("%d: hello world\n", d.count)
}

func main() {
	c := cron.New()
	_, _ = c.AddJob("@every 1s", cron.NewChain(cron.SkipIfStillRunning(cron.DefaultLogger)).Then(&delayJob{}))
	c.Start()

	time.Sleep(10 * time.Second)
}

 ~/go/src/GoWebDemo/studygolang/cron   master ✚ ●  go run demo.go                                                                                                                     
2020/09/04 16:16:03 1: hello world
2020/09/04 16:16:05 2: hello world
2020/09/04 16:16:08 3: hello world
```





```go
func (d *delayJob) Run() {
	time.Sleep(2 * time.Second)
	d.count++
	log.Printf("%d: hello world\n", d.count)
}

func main() {
	c := cron.New()
	_, _ = c.AddJob("@every 1s", cron.NewChain(cron.DelayIfStillRunning(cron.DefaultLogger)).Then(&delayJob{}))
	c.Start()

	time.Sleep(10 * time.Second)
}


 ~/go/src/GoWebDemo/studygolang/cron   master ✚ ●  go run demo.go                                                                                                                    
2020/09/04 16:18:07 1: hello world
2020/09/04 16:18:09 2: hello world
2020/09/04 16:18:11 3: hello world
2020/09/04 16:18:13 4: hello world
```

