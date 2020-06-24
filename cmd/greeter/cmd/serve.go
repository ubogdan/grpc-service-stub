/*
Copyright © 2020 Tino Rusch <tino.rusch@contiamo.com>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
*/
package cmd

import (
	"context"
	"os"
	"os/signal"

	"github.com/contiamo/goserver"
	grpcserver "github.com/contiamo/goserver/grpc"
	"github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
	"github.com/trusch/grpc-service-stub/pkg/grpc/services/greeter"
	greeterapi "github.com/trusch/grpc-service-stub/pkg/protobuf/greeter"
	"google.golang.org/grpc"
)

// serveCmd represents the serve command
var serveCmd = &cobra.Command{
	Use:   "serve",
	Short: "A brief description of your command",
	Long: `A longer description that spans multiple lines and likely contains examples
and usage of using your command. For example:

Cobra is a CLI library for Go that empowers applications.
This application is a tool to generate the needed files
to quickly create a Cobra application.`,
	Run: func(cmd *cobra.Command, args []string) {
		ctx, cancel := context.WithCancel(context.Background())
		c := make(chan os.Signal, 1)
		signal.Notify(c, os.Interrupt)
		go func() {
			<-c
			cancel()
		}()

		listenAddr, _ := cmd.Flags().GetString("addr")
		metricsAddr, _ := cmd.Flags().GetString("metrics")

		grpcServer, err := grpcserver.New(&grpcserver.Config{
			Options: []grpcserver.Option{
				grpcserver.WithCredentials("", "", ""),
				grpcserver.WithLogging("greeter"),
				grpcserver.WithMetrics(),
				grpcserver.WithRecovery(),
				grpcserver.WithReflection(),
			},
			Extras: []grpc.ServerOption{
				grpc.MaxSendMsgSize(1 << 12),
			},
			Register: func(srv *grpc.Server) {
				greeterServer, err := greeter.New()
				if err != nil {
					logrus.Fatal(err)
				}
				greeterapi.RegisterGreeterServer(srv, greeterServer)
			},
		})
		if err != nil {
			logrus.Fatal(err)
		}

		go goserver.ListenAndServeMonitoring(ctx, metricsAddr, nil)

		// start server
		if err := grpcserver.ListenAndServe(ctx, listenAddr, grpcServer); err != nil {
			logrus.Fatal(err)
		}

	},
}

func init() {
	rootCmd.AddCommand(serveCmd)
	serveCmd.Flags().String("addr", ":3001", "gRPC listening address")
	serveCmd.Flags().String("metrics", ":8080", "metrics listening address")
}
