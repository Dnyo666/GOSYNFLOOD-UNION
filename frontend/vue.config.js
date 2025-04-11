module.exports = {
  // 关闭eslint校验
  lintOnSave: false,
  // 生产环境不生成sourceMap
  productionSourceMap: false,
  // 配置开发服务器
  devServer: {
    port: 38721,
    // 配置API代理
    proxy: {
      '/api': {
        target: 'http://localhost:31457',
        changeOrigin: true
      },
      '/ws': {
        target: 'ws://localhost:31457',
        ws: true,
        changeOrigin: true
      }
    }
  },
  // 输出目录配置
  outputDir: '../backend/static',
  // 静态资源目录
  assetsDir: 'assets',
  // 生产环境优化
  configureWebpack: {
    optimization: {
      splitChunks: {
        chunks: 'all'
      }
    }
  }
} 