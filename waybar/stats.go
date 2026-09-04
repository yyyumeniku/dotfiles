// To build go build -o stats stats.go

package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"math"
	"os"
	"os/exec"
	"regexp"
	"strconv"
	"strings"
	"time"
)

const (
	barCells = 15
	dimColor = "#3f3f3f"
	redColor = "#e05252"

	iconCPU = "\uf2db"
	iconRAM = "\uefc5"
	iconLow = "\uf026"
	iconMid = "\uf027"
	iconHi  = "\uf028"

	block = "\u2581"
)

type out struct {
	Text    string `json:"text"`
	Tooltip string `json:"tooltip"`
}

func mixColor(c1, c2 string, t float64) string {
	parse := func(s string) [3]float64 {
		var c [3]float64
		for i := 0; i < 3; i++ {
			v, _ := strconv.ParseInt(s[1+2*i:3+2*i], 16, 32)
			c[i] = float64(v)
		}
		return c
	}
	a, b := parse(c1), parse(c2)
	if t < 0 {
		t = 0
	}
	if t > 1 {
		t = 1
	}
	var sb strings.Builder
	sb.WriteByte('#')
	for i := 0; i < 3; i++ {
		v := int(math.Round(a[i] + (b[i]-a[i])*t))
		sb.WriteString(fmt.Sprintf("%02x", v))
	}
	return sb.String()
}

func bar(color string, pct float64) string {
	filled := int(math.Round(pct / 100.0 * barCells))
	if filled < 0 {
		filled = 0
	}
	if filled > barCells {
		filled = barCells
	}
	on := strings.Repeat(block, filled)
	off := strings.Repeat(block, barCells-filled)
	markup := fmt.Sprintf(`<span foreground="%s">%s</span><span foreground="%s">%s</span>`,
		color, on, dimColor, off)
	return fmt.Sprintf(`<span size="xx-small">%s</span>`, markup)
}

func emit(line1, color string, pct float64, tip string) {
	text := fmt.Sprintf(`%s%s<span foreground="%s">%s</span>`,
		bar(color, pct), "\n", color, line1)
	b, _ := json.Marshal(out{Text: text, Tooltip: tip})
	fmt.Println(string(b))
}

func cpuUsage() float64 {
	sample := func() (total, idle float64) {
		f, err := os.Open("/proc/stat")
		if err != nil {
			return 0, 0
		}
		defer f.Close()
		r := bufio.NewReader(f)
		line, _ := r.ReadString('\n')
		fields := strings.Fields(line)
		for i, v := range fields {
			if i == 0 {
				continue
			}
			n, _ := strconv.ParseFloat(v, 64)
			total += n
			if i == 4 || i == 5 {
				idle += n
			}
		}
		return total, idle
	}
	t1, i1 := sample()
	time.Sleep(150 * time.Millisecond)
	t2, i2 := sample()
	dt, di := t2-t1, i2-i1
	if dt <= 0 {
		return 0
	}
	return 100.0 * (1.0 - di/dt)
}

func memory() (usedGB, totalGB, pct float64) {
	vals := map[string]float64{}
	f, err := os.Open("/proc/meminfo")
	if err != nil {
		return 0, 0, 0
	}
	defer f.Close()
	s := bufio.NewScanner(f)
	for s.Scan() {
		fields := strings.Fields(s.Text())
		if len(fields) < 2 {
			continue
		}
		n, _ := strconv.ParseFloat(fields[1], 64)
		vals[strings.TrimSuffix(fields[0], ":")] = n
	}
	totalKB := vals["MemTotal"]
	availKB := vals["MemAvailable"]
	if availKB == 0 {
		availKB = vals["MemFree"] + vals["Buffers"] + vals["Cached"]
	}
	usedKB := totalKB - availKB
	return usedKB / 1024 / 1024, totalKB / 1024 / 1024, 100.0 * usedKB / totalKB
}

func volume() (pct float64, muted bool) {
	outB, err := exec.Command("wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@").Output()
	if err != nil {
		return 0, false
	}
	low := strings.ToLower(string(outB))
	if strings.Contains(low, "[muted]") || strings.Contains(low, "muted: yes") {
		muted = true
	}
	re := regexp.MustCompile(`([0-9.]+)`)
	if m := re.FindString(low); m != "" {
		v, _ := strconv.ParseFloat(m, 64)
		pct = v * 100.0
	}
	return pct, muted
}

func emitVolume() {
	pct, muted := volume()
	icon := iconLow
	if pct >= 34 {
		icon = iconMid
	}
	if pct >= 67 {
		icon = iconHi
	}
	line1 := fmt.Sprintf("%s  %.0f%%", icon, pct)
	if muted {
		line1 = fmt.Sprintf(`<span foreground="#5c5c5c">%s</span>`, line1)
	}
	tip := fmt.Sprintf("Volume %.0f%%", pct)
	if muted {
		tip += " (muted)"
	}
	emit(line1, "#ffffff", pct, tip)
}

func volumeLoop() {
	emitVolume()
	pactl, err := exec.LookPath("pactl")
	if err != nil {
		for {
			time.Sleep(500 * time.Millisecond)
			emitVolume()
		}
	}
	cmd := exec.Command(pactl, "subscribe")
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return
	}
	if err := cmd.Start(); err != nil {
		return
	}
	defer cmd.Wait()
	s := bufio.NewScanner(stdout)
	re := regexp.MustCompile(`'change' on (sink|server) `)
	for s.Scan() {
		if re.MatchString(s.Text()) {
			emitVolume()
		}
	}
}

func main() {
	kind := "cpu"
	if len(os.Args) > 1 {
		kind = os.Args[1]
	}

	switch kind {
	case "cpu":
		pct := cpuUsage()
		color := mixColor("#a78bfa", redColor, pct/100.0)
		emit(fmt.Sprintf("%s  %.0f%%", iconCPU, pct), color, pct,
			fmt.Sprintf("CPU %.0f%%", pct))
	case "memory":
		usedGB, totalGB, pct := memory()
		color := mixColor("#7bd88f", redColor, pct/100.0)
		emit(fmt.Sprintf("%s  %.1fG", iconRAM, usedGB), color, pct,
			fmt.Sprintf("RAM %.1fG / %.1fG (%.0f%%)", usedGB, totalGB, pct))
	case "volume":
		emitVolume()
	case "volume-loop":
		volumeLoop()
	}
}
