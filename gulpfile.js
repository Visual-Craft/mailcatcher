'use strict';

const gulp = require('gulp');
const sass = require('gulp-sass');
const autoprefixer = require('gulp-autoprefixer');
const concat = require('gulp-concat');
const csso = require('gulp-csso');
const uglify = require('gulp-uglify');
const coffee = require('gulp-coffee');

const paths = {
    styles: [
        __dirname + '/assets/stylesheets/*.scss'
    ],
    appScripts: [
        __dirname + '/assets/javascripts/*.coffee'
    ],
    vendorScripts: [
        require.resolve('jquery/dist/jquery.js'),
        require.resolve('keymaster/keymaster.js'),
        require.resolve('underscore/underscore.js'),
        require.resolve('moment/min/moment-with-locales.js'),
        require.resolve('vue/dist/vue.min.js'),
        require.resolve('noty/js/noty/packaged/jquery.noty.packaged.js'),
        require.resolve('js-cookie/src/js.cookie.js'),
        require.resolve('reconnectingwebsocket/reconnecting-websocket.js')
    ]
};

gulp.task('css', function() {
    return gulp.src(paths.styles)
        .pipe(sass.sync().on('error', sass.logError))
        .pipe(autoprefixer({
            browsers: ['last 2 versions'],
            cascade: false
        }))
        .pipe(concat('mailcatcher.css'))
        .pipe(csso())
        .pipe(gulp.dest(__dirname + '/public/assets'))
    ;
});

gulp.task('vendor-js', function() {
    return gulp.src(paths.vendorScripts)
        .pipe(concat('vendor.js'))
        .pipe(uglify())
        .pipe(gulp.dest(__dirname + '/public/assets'))
    ;
});

gulp.task('app-js', function() {
    return gulp.src(paths.appScripts)
        .pipe(coffee({bare: false}))
        .pipe(concat('mailcatcher.js'))
        .pipe(uglify())
        .pipe(gulp.dest(__dirname + '/public/assets'))
    ;
});

gulp.task('watch:css', function () {
    gulp.watch(paths.styles, gulp.series('css'));
});

gulp.task('watch:app-js', function () {
    gulp.watch(paths.appScripts, gulp.series('app-js'));
});

gulp.task('watch:vendor-js', function () {
    gulp.watch(paths.vendorScripts, gulp.series('vendor-js'));
});

gulp.task('watch', gulp.series(
    gulp.parallel('css', 'vendor-js', 'app-js'),
    gulp.parallel('watch:css', 'watch:app-js', 'watch:vendor-js')
));

gulp.task('build', gulp.parallel('css', 'vendor-js', 'app-js'));
gulp.task('default', gulp.task('build'));
